import * as z from 'zod';
import { dialNodeDataSchema } from '$lib/server/types/DialNodeData';
import { weekTimeSchema } from '$lib/server/types/WeekTimeData';
import { playNodeDataSchema } from '$lib/types/PlayNodeData';
import { queueNodeDataSchema } from '$lib/types/QueueNodeData';
import { dialGroupNodeDataSchema } from '$lib/server/types/DialGroupNodeData';
import { menuNodeDataSchema } from '$lib/types/MenuNodeData';
import { voiceBotNodeDataSchema } from '$lib/types/VoiceBotNodeData';

export const inboundFlowGraphDataSchema = z.object({
  start: z.string(),
  nodes: z.record(
    z.string(),
    z.union([
      dialNodeDataSchema,
      weekTimeSchema,
      playNodeDataSchema,
      queueNodeDataSchema,
      dialGroupNodeDataSchema,
      menuNodeDataSchema,
      voiceBotNodeDataSchema,
    ]),
  ),
});

export type InboundFlowGraphData = z.infer<typeof inboundFlowGraphDataSchema>;
