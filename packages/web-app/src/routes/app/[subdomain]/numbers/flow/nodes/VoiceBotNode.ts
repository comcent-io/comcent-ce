import VoiceBotNodeComponent from './VoiceBotNode.svelte';
import { v4 as uuidv4 } from 'uuid';
import { FlowNode } from './FlowNode';
import type { VoiceBotNodeData } from '$lib/types/VoiceBotNodeData';

export class VoiceBotNode extends FlowNode {
  data: VoiceBotNodeData;
  component = VoiceBotNodeComponent;
  constructor(data?: VoiceBotNodeData) {
    super();
    if (data) {
      this.data = data;
    } else {
      this.data = {
        id: uuidv4(),
        type: 'VoiceBot',
        data: {
          voiceBotName: '',
          voiceBotId: '',
        },
      };
    }
  }

  linkOutletToInlet() {
    return null;
  }
}
