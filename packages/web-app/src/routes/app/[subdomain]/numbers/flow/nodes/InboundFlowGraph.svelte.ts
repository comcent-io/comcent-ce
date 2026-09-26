import { DialNode } from './DialNode';
import type { FlowNode } from './FlowNode.svelte';
import type { InboundFlowGraphData } from '$lib/types/InboundFlowGraphData';
import { WeekTimeNode } from './WeekTimeNode';
import { PlayNode } from './PlayNode';
import { QueueNode } from './QueueNode';
import { DialGroupNode } from './DialGroupNode';
import { MenuNode } from './MenuNode';
import { VoiceBotNode } from './VoiceBotNode';

// Reactive (runes in a .svelte.ts module): adding, removing or relinking a
// node updates the flow builder without any manual invalidation.
export class InboundFlowGraph {
  nodes: Record<string, FlowNode> = $state({});
  start = $state('');

  constructor(inboundFlowGraph: string | object) {
    const data = this.parse(inboundFlowGraph);
    this.start = data.start;
    for (const node of Object.values(data.nodes)) {
      switch (node.type) {
        case 'Dial':
          this.nodes[node.id] = new DialNode(node);
          break;
        case 'WeekTime':
          this.nodes[node.id] = new WeekTimeNode(node);
          break;
        case 'Play':
          this.nodes[node.id] = new PlayNode(node);
          break;
        case 'Queue':
          this.nodes[node.id] = new QueueNode(node);
          break;
        case 'DialGroup':
          this.nodes[node.id] = new DialGroupNode(node);
          break;
        case 'Menu':
          this.nodes[node.id] = new MenuNode(node);
          break;
        case 'VoiceBot':
          this.nodes[node.id] = new VoiceBotNode(node);
          break;
        default:
          break;
      }
    }
  }

  private parse(inboundFlowGraph: string | object): InboundFlowGraphData {
    const emptyGraph: InboundFlowGraphData = {
      start: '',
      nodes: {},
    };

    if (!inboundFlowGraph) {
      return emptyGraph;
    }

    if (typeof inboundFlowGraph !== 'string') {
      const graph = inboundFlowGraph as Partial<InboundFlowGraphData>;
      return {
        start: graph.start ?? '',
        nodes: graph.nodes ?? {},
      } as InboundFlowGraphData;
    }

    const trimmedGraph = inboundFlowGraph.trim();
    if (!trimmedGraph) {
      return emptyGraph;
    }

    try {
      const parsedGraph = JSON.parse(trimmedGraph) as Partial<InboundFlowGraphData>;
      return {
        start: parsedGraph.start ?? '',
        nodes: parsedGraph.nodes ?? {},
      };
    } catch {
      return emptyGraph;
    }
  }

  addNode(node: FlowNode) {
    this.nodes[node.data.id] = node;
  }

  removeNode(id: string) {
    delete this.nodes[id];
  }

  json() {
    const data = {
      start: this.start,
      nodes: {} as any,
    };
    for (const node of Object.values(this.nodes)) {
      data.nodes[node.data.id] = node.data;
    }
    return JSON.stringify(data);
  }
}
