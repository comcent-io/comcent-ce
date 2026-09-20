import { execFile } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import path from 'node:path';
import { promisify } from 'node:util';
import { fileURLToPath } from 'node:url';

const execFileAsync = promisify(execFile);
const repoRoot = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  '..',
  '..',
);

/**
 * Path to the committed customer speech PCAP used to simulate the customer
 * side of a two-way conversation.  See e2e/telephony/audio/README.md.
 */
export const CUSTOMER_PCAP_HOST_PATH = path.join(
  repoRoot,
  'e2e/telephony/audio/customer.pcap',
);
const CUSTOMER_PCAP_CONTAINER_PATH = '/tmp/customer-audio.pcap';

export const DTMF_PCAP_HOST_PATH = path.join(
  repoRoot,
  'e2e/telephony/audio/dtmf-1.pcap',
);
const DTMF_PCAP_CONTAINER_PATH = '/tmp/dtmf.pcap';

const composeArgs = [
  'compose',
  '-f',
  'docker-compose-e2e.yaml',
  '--env-file',
  '.env.e2e',
  '-p',
  'comcent-e2e',
];

const SBC_SERVICE = 'sbc';

type SippRunOptions = {
  scenario: string;
  targetHost?: string;
  targetPort?: number;
  service?: string;
  csvRows?: string[];
  extraArgs?: string[];
  rtpEcho?: boolean;
  timeoutMs?: number;
  allowNonZeroExit?: boolean;
  resetProcesses?: boolean;
};

type RegisteredAgentOptions = {
  username: string;
  password: string;
  domain?: string;
  service?: string;
  localPort?: number;
  behavior?: 'accept' | 'reject';
  timeoutMs?: number;
  /**
   * When true the UAS answers with `uas-answer-pcap-remote-bye.xml` which
   * plays `customer.pcap` toward FreeSwitch and holds the call for ~15 s
   * before sending BYE.  Ignored when `behavior` is `'reject'`.
   */
  withAudio?: boolean;
};

async function runCompose(
  args: string[],
  timeoutMs = 60_000,
  allowNonZeroExit = false,
) {
  try {
    const { stdout, stderr } = await execFileAsync('docker', args, {
      cwd: repoRoot,
      timeout: timeoutMs,
      maxBuffer: 8 * 1024 * 1024,
    });

    return { stdout, stderr, exitCode: 0 };
  } catch (error) {
    if (
      allowNonZeroExit &&
      typeof error === 'object' &&
      error !== null &&
      'stdout' in error &&
      'stderr' in error
    ) {
      return {
        stdout: String(error.stdout ?? ''),
        stderr: String(error.stderr ?? ''),
        exitCode: Number('code' in error ? error.code : 1) || 1,
      };
    }

    throw error;
  }
}

export async function runSipp(options: SippRunOptions) {
  const targetHost = options.targetHost;
  const targetPort = options.targetPort ?? 5060;
  const service = options.service ?? 'sipp';
  const csvRows = options.csvRows ?? [];
  const extraArgs = options.extraArgs ?? [];
  const rtpEcho = options.rtpEcho ?? false;
  const timeoutMs = options.timeoutMs ?? 90_000;
  const resetProcesses = options.resetProcesses ?? false;

  // The SIPp containers are shared by every Playwright worker, so this path
  // must be unique across processes. A per-process counter is not: workers
  // running the same spec in lock-step reach the same counter value in the
  // same millisecond, and one test's SIPp then reads another test's row.
  const csvPath = `/tmp/sipp_${randomUUID()}.csv`;
  const csvArg = csvRows.length > 0 ? `-inf ${csvPath}` : '';
  const csvContent = ['SEQUENTIAL', ...csvRows]
    .map((row) => row)
    .join('\n')
    .replaceAll("'", "'\"'\"'");

  const targetArg = targetHost ? `${targetHost}:${targetPort}` : '';
  const command = [
    'sh',
    '-c',
    [
      resetProcesses ? 'pkill -x sipp 2>/dev/null; sleep 1; true' : 'true',
      csvRows.length > 0
        ? `cat <<'EOF' >${csvPath}\n${csvContent}\nEOF`
        : 'true',
      [
        'sipp',
        targetArg,
        '-sf',
        `/scenarios/${options.scenario}`,
        csvArg,
        '-trace_err',
        '-trace_msg',
        '-nostdin',
        '-m',
        '1',
        ...(rtpEcho ? ['-rtp_echo'] : []),
        ...extraArgs,
      ]
        .filter(Boolean)
        .join(' '),
    ].join('\n'),
  ];

  return runCompose(
    [...composeArgs, 'exec', '-T', service, ...command],
    timeoutMs,
    options.allowNonZeroExit ?? false,
  );
}

/**
 * Stops the SIPp instances bound to the given local ports, and only those.
 * The SIPp containers are shared by every Playwright worker, so a blanket
 * `pkill sipp` also kills the agents of whichever specs happen to be running
 * in parallel, which then fail with an agent that never answered.
 */
export async function stopSippProcesses(
  targets: Array<{
    service: 'sipp' | 'sipp-uas' | 'sipp-agent-a' | 'sipp-agent-b';
    port: number;
  }>,
) {
  const portsByService = new Map<string, Set<number>>();
  for (const { service, port } of targets) {
    const ports = portsByService.get(service) ?? new Set<number>();
    ports.add(port);
    portsByService.set(service, ports);
  }

  await Promise.allSettled(
    [...portsByService].map(([service, ports]) =>
      runCompose(
        [
          ...composeArgs,
          'exec',
          '-T',
          service,
          'sh',
          '-c',
          `pkill -f '^sipp .* -p (${[...ports].join('|')})( |$)' || true`,
        ],
        30_000,
        true,
      ),
    ),
  );
}

export async function runInboundDidToExternalFlow(params: {
  customerNumber: string;
  didNumber: string;
  externalTarget: string;
  answerAfterMs?: number;
  hangupAfterMs?: number;
  callerScenario?: string;
  uasScenario?: string;
  externalService?: string;
  externalPort?: number;
  callerPort?: number;
  callerCsvFields?: string[];
  callerExtraArgs?: string[];
  /**
   * When true the UAS plays `customer.pcap` toward FreeSwitch for the
   * duration of the call.  Switches the default UAS scenario to
   * `uas-answer-pcap.xml` and bumps the default caller-side hangup to 15 s
   * so the full 17 s speech clip has a chance to play back.
   */
  withAudio?: boolean;
  /**
   * When true the caller plays `dtmf-1.pcap` toward FreeSwitch via the RTP
   * media plane (RFC 2833 telephone-event packets).  Switches the default
   * caller scenario to `uac-dtmf-pcap-remote-bye.xml` which waits for
   * remote BYE after playing the DTMF events.
   */
  withDtmf?: boolean;
}) {
  void params.answerAfterMs;
  void params.externalTarget;
  const withAudio = params.withAudio ?? false;
  const withDtmf = params.withDtmf ?? false;
  const hangupAfterMs = params.hangupAfterMs ?? (withAudio ? 15_000 : 3_000);
  const externalService = params.externalService ?? 'sipp-uas';
  const externalPort = params.externalPort ?? 5060;
  const callerService = 'sipp';
  const uasScenario =
    params.uasScenario ??
    (withAudio ? 'uas-answer-pcap.xml' : 'uas-answer.xml');
  const callerScenario =
    params.callerScenario ?? (withDtmf ? 'uac-dtmf-pcap.xml' : 'uac-basic.xml');

  if (withAudio) {
    await copyFileToContainer(
      CUSTOMER_PCAP_HOST_PATH,
      externalService,
      CUSTOMER_PCAP_CONTAINER_PATH,
    );
  }

  if (withDtmf) {
    await copyFileToContainer(
      DTMF_PCAP_HOST_PATH,
      callerService,
      DTMF_PCAP_CONTAINER_PATH,
    );
  }

  const uas = runSipp({
    scenario: uasScenario,
    service: externalService,
    extraArgs: ['-p', String(externalPort), '-t', 'u1'],
    timeoutMs: 120_000,
  });

  await new Promise((resolve) => setTimeout(resolve, 1500));

  const uac = runSipp({
    scenario: callerScenario,
    targetHost: 'sbc',
    targetPort: 5060,
    csvRows: [
      [
        params.customerNumber,
        params.didNumber,
        ...(params.callerCsvFields ?? []),
        `${hangupAfterMs}`,
      ].join(';'),
    ],
    extraArgs: [
      '-p',
      String(params.callerPort ?? 5060),
      '-t',
      'u1',
      ...(params.callerExtraArgs ?? []),
    ],
    timeoutMs: 120_000,
  });

  const [uasResult, uacResult] = await Promise.all([uas, uac]);
  return { uasResult, uacResult };
}

export async function runInboundDidCall(params: {
  customerNumber: string;
  didNumber: string;
  hangupAfterMs?: number;
  scenario?: string;
  callerService?: string;
  localPort?: number;
  callerExtraArgs?: string[];
  resetProcesses?: boolean;

  /**
   * When true the customer-side PCAP is copied into the caller container and
   * play-audio.sh is invoked (via the UAC scenario) so FreeSwitch receives
   * real customer speech instead of silence.  Callers that need the PCAP
   * must pick a UAC scenario that calls play-audio.sh, e.g.
   * `uac-remote-bye-pcap.xml`.
   */
  withAudio?: boolean;
}) {
  const hangupAfterMs = params.hangupAfterMs ?? 3_000;
  const callerService = params.callerService ?? 'sipp';

  if (params.withAudio) {
    await copyFileToContainer(
      CUSTOMER_PCAP_HOST_PATH,
      callerService,
      CUSTOMER_PCAP_CONTAINER_PATH,
    );
  }

  return runSipp({
    scenario: params.scenario ?? 'uac-basic.xml',
    targetHost: 'sbc',
    targetPort: 5060,
    service: callerService,
    csvRows: [`${params.customerNumber};${params.didNumber};${hangupAfterMs}`],
    extraArgs: [
      '-p',
      String(params.localPort ?? 5060),
      '-t',
      'u1',
      ...(params.callerExtraArgs ?? []),
    ],
    timeoutMs: 120_000,
    resetProcesses: params.resetProcesses,
  });
}

export async function runRegisteredSipAgent(params: RegisteredAgentOptions) {
  const service = params.service ?? 'sipp-agent-a';
  const contactPort = params.localPort ?? 5066;
  const registerPort = contactPort + 100;
  const domain = params.domain ?? 'acme.comcent.io';
  const rejecting = params.behavior === 'reject';
  const withAudio = !rejecting && (params.withAudio ?? false);
  const uasScenario = rejecting
    ? 'uas-reject.xml'
    : withAudio
      ? 'uas-answer-pcap-remote-bye.xml'
      : 'uas-answer-remote-bye.xml';

  if (withAudio) {
    await copyFileToContainer(
      CUSTOMER_PCAP_HOST_PATH,
      service,
      CUSTOMER_PCAP_CONTAINER_PATH,
    );
  }
  const timeoutMs = params.timeoutMs ?? 150_000;
  const csvContent = [
    'SEQUENTIAL',
    `${params.username};${params.password};${domain};${contactPort}`,
  ]
    .join('\n')
    .replaceAll("'", "'\"'\"'");

  const script = [
    'pkill -f "^sipp " >/dev/null 2>&1 || true',
    `cat <<'EOF' >/tmp/sipp-agent.csv\n${csvContent}\nEOF`,
    `sipp -sf /scenarios/${uasScenario} -trace_err -trace_msg -nostdin -m 1 -p ${contactPort} -t u1 >/tmp/${params.username}-uas.log 2>&1 &`,
    'uas_pid=$!',
    'sleep 1',
    [
      'sipp',
      'sbc:5065',
      '-sf',
      '/scenarios/uac-register-only.xml',
      '-inf',
      '/tmp/sipp-agent.csv',
      '-trace_err',
      '-trace_msg',
      '-nostdin',
      '-m',
      '1',
      '-p',
      String(registerPort),
      '-t',
      'u1',
      '-au',
      params.username,
      '-ap',
      params.password,
      '-auth_uri',
      domain,
      '-s',
      params.username,
    ].join(' '),
    'register_status=$?',
    'if [ "$register_status" -ne 0 ]; then kill "$uas_pid" >/dev/null 2>&1 || true; wait "$uas_pid" >/dev/null 2>&1 || true; exit "$register_status"; fi',
    'wait "$uas_pid"',
    'uas_status=$?',
    [
      'sipp',
      'sbc:5065',
      '-sf',
      '/scenarios/uac-unregister-only.xml',
      '-inf',
      '/tmp/sipp-agent.csv',
      '-trace_err',
      '-trace_msg',
      '-nostdin',
      '-m',
      '1',
      '-p',
      String(registerPort),
      '-t',
      'u1',
      '-au',
      params.username,
      '-ap',
      params.password,
      '-auth_uri',
      domain,
      '-s',
      params.username,
    ].join(' '),
    'exit "$uas_status"',
  ].join('\n');

  return runCompose(
    [...composeArgs, 'exec', '-T', service, 'sh', '-lc', script],
    timeoutMs,
    false,
  );
}

/**
 * Runs SIPp's `uac-register-only.xml` against Kamailio and resolves only
 * after the authenticated REGISTER's `200 OK` is received (SIPp exits 0
 * once the scenario completes).  This is an SIP-protocol edge-level
 * signal — no component-specific polling required.
 *
 * Both REGISTER and the subsequent UAS share the same local port so
 * Kamailio's NAT detection (`received=...`) doesn't route INVITEs to a
 * dead port; pair this with `unregisterSipAgentInline` for symmetry.
 */
export async function registerSipAgentInline(params: {
  username: string;
  password: string;
  domain?: string;
  service: string;
  port: number;
  timeoutMs?: number;
}) {
  const domain = params.domain ?? 'acme.comcent.io';
  return runSipp({
    scenario: 'uac-register-only.xml',
    service: params.service,
    targetHost: 'sbc',
    targetPort: 5065,
    csvRows: [`${params.username};${params.password};${domain};${params.port}`],
    extraArgs: [
      '-p',
      String(params.port),
      '-t',
      'u1',
      '-au',
      params.username,
      '-ap',
      params.password,
      '-auth_uri',
      domain,
      '-s',
      params.username,
    ],
    timeoutMs: params.timeoutMs ?? 30_000,
  });
}

export async function unregisterSipAgentInline(params: {
  username: string;
  password: string;
  domain?: string;
  service: string;
  port: number;
  timeoutMs?: number;
}) {
  const domain = params.domain ?? 'acme.comcent.io';
  return runSipp({
    scenario: 'uac-unregister-only.xml',
    service: params.service,
    targetHost: 'sbc',
    targetPort: 5065,
    csvRows: [`${params.username};${params.password};${domain};${params.port}`],
    extraArgs: [
      '-p',
      String(params.port),
      '-t',
      'u1',
      '-au',
      params.username,
      '-ap',
      params.password,
      '-auth_uri',
      domain,
      '-s',
      params.username,
    ],
    timeoutMs: params.timeoutMs ?? 30_000,
    allowNonZeroExit: true,
  });
}

export async function killAllSippProcesses() {
  const services = ['sipp', 'sipp-uas', 'sipp-agent-a', 'sipp-agent-b'];
  await Promise.all(
    services.map((s) =>
      runCompose(
        [
          ...composeArgs,
          'exec',
          '-T',
          s,
          'sh',
          '-c',
          'pkill -x sipp 2>/dev/null; true',
        ],
        10_000,
        true,
      ),
    ),
  );
}

/**
 * FreeSWITCH reads the system clock once at startup and from then on advances
 * its own clock from a monotonic timer. That timer stops while the Docker VM
 * is suspended (laptop sleep), so on a long-lived local stack FreeSWITCH falls
 * behind by however long the machine slept. A call story then starts in
 * FreeSWITCH's past but ends at the server's "now", so a 10 second call is
 * recorded as hours long and every assertion on durations or ordering is
 * working with nonsense. `fsctl sync_clock` re-reads the system clock.
 */
export async function syncFreeSwitchClock() {
  await runCompose(
    [
      ...composeArgs,
      'exec',
      '-T',
      'freeswitch',
      'fs_cli',
      '-x',
      'fsctl sync_clock',
    ],
    30_000,
    true,
  );
}

export async function restartServer() {
  await runCompose([...composeArgs, 'restart', 'server'], 60_000, true);
}

export async function waitForServerHealthy() {
  const deadline = Date.now() + 60_000;
  while (Date.now() < deadline) {
    const result = await runCompose(
      [
        ...composeArgs,
        'exec',
        '-T',
        'server',
        'sh',
        '-c',
        'curl -sf http://127.0.0.1:4000/health >/dev/null 2>&1 && echo ok',
      ],
      10_000,
      true,
    );
    if (result.stdout.trim() === 'ok') return;
    await new Promise((r) => setTimeout(r, 2_000));
  }
  throw new Error('Server did not become healthy within 60s');
}

export async function waitForSbcDispatcher() {
  const rpcToken = process.env.RPC_API_TOKEN || '';
  const fsIP = process.env.E2E_FREESWITCH_IP || '172.29.17.8';

  const rpc = (body: string) => [
    ...composeArgs,
    'exec',
    '-T',
    SBC_SERVICE,
    'sh',
    '-c',
    `curl -sf -H "X-Api-Token: ${rpcToken}" -d '${body}' http://127.0.0.1:80/rpc 2>/dev/null`,
  ];

  await runCompose(
    rpc(
      `{"jsonrpc":"2.0","method":"dispatcher.add","params":[2,"sip:${fsIP}:5070"],"id":1}`,
    ),
    10_000,
    true,
  );

  const deadline = Date.now() + 30_000;
  while (Date.now() < deadline) {
    const result = await runCompose(
      rpc('{"jsonrpc":"2.0","method":"dispatcher.list","id":1}'),
      10_000,
      true,
    );
    if (result.stdout.includes('sip:')) return;
    await new Promise((r) => setTimeout(r, 2_000));
  }
  throw new Error('SBC dispatcher has no destinations after 30s');
}

/**
 * Copies a file from the host into a running compose service container.
 * Equivalent to: docker compose cp <localPath> <service>:<containerPath>
 */
export async function copyFileToContainer(
  localPath: string,
  service: string,
  containerPath: string,
) {
  await execFileAsync(
    'docker',
    [...composeArgs, 'cp', localPath, `${service}:${containerPath}`],
    { cwd: repoRoot, timeout: 30_000 },
  );
}

export async function readLatestSippMessagesLog(
  service: string,
  prefix: string,
) {
  const { stdout } = await runCompose(
    [
      ...composeArgs,
      'exec',
      '-T',
      service,
      'sh',
      '-lc',
      `latest=$(ls -1t /tmp/${prefix}*_messages.log 2>/dev/null | head -n 1) && [ -n "$latest" ] && cat "$latest"`,
    ],
    30_000,
  );

  return stdout;
}
