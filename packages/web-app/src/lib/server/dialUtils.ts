import { parsePhoneNumber } from 'libphonenumber-js';

const SBC_IP = process.env.SBC_IP;
// Target the SBC's PRIVATE listener (5065). 5060 is the public/PSTN-facing
// leg; sending FS outbound there would loop back through public routing.
const SBC_SIP_URI = SBC_IP ? `sip:${SBC_IP}:5065` : '';
const SIP_USER_ROOT_DOMAIN =
  process.env.SIP_USER_ROOT_DOMAIN ||
  (process.env.PUBLIC_BASE_URL ? new URL(process.env.PUBLIC_BASE_URL).hostname : undefined);
if (!SIP_USER_ROOT_DOMAIN) {
  throw new Error('PUBLIC_BASE_URL (or SIP_USER_ROOT_DOMAIN override) env var is required');
}

export function createDialStringForUser(username: string, subdomain: string) {
  const dString = `sofia/internal/${username}@${subdomain}.${SIP_USER_ROOT_DOMAIN};fs_path=${SBC_SIP_URI}`;
  return [dString, `[media_webrtc=true]${dString}`].join(',');
}

export function createDialStringForSipTrunk(
  fromNumber: string,
  toNumber: string,
  trunkAddress: string,
  spoofedNumber?: string,
) {
  // Next two lines convert the number to E164 or US11 format
  // as some sip trunk requires US11 format using fromNumber as reference
  const adjustedToNumber = convertNumberToE164OrUs11(fromNumber, toNumber);
  const adjustedSpoofedNumber = spoofedNumber
    ? convertNumberToE164OrUs11(fromNumber, spoofedNumber)
    : undefined;
  const variables = `[sip_h_X-Trunk-Number=${fromNumber},origination_caller_id_number=${
    adjustedSpoofedNumber || fromNumber
  }]`;
  return `${variables}sofia/internal/${adjustedToNumber}@${trunkAddress};fs_path=${SBC_SIP_URI}`;
}

export function convertNumberToE164OrUs11(referenceNumber: string, numberToBeConverted: string) {
  const isUs11 = referenceNumber.length === 11 && referenceNumber.startsWith('1');
  const referenceNumberInE164 = isUs11 ? `+${referenceNumber}` : referenceNumber;
  const parsedReference = parsePhoneNumber(referenceNumberInE164);
  let parsedNumberToBeConverted = parsePhoneNumber(numberToBeConverted, parsedReference.country);
  if (!parsedNumberToBeConverted.isValid()) {
    parsedNumberToBeConverted = parsePhoneNumber(`+${numberToBeConverted}`);
  }
  const theConvertedNumber = parsedNumberToBeConverted.number;
  return isUs11 ? theConvertedNumber.replace('+', '') : theConvertedNumber;
}
