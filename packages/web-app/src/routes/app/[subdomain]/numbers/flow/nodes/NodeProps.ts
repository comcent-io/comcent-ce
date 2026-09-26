import type { DragEnd } from '../utils/Draggable.svelte';
import type { SelectedInlet } from '../SelectedInlet';
import type { SelectedOutlet } from '../SelectedOutlet';
import type { FlowNode } from './FlowNode.svelte';

export type UploadStatus = { nodeId: string; status: 'uploading' | 'completed' };

/** What FlowDiagram passes to every node component. */
export interface NodeProps<TNode extends FlowNode = FlowNode> {
  node: TNode;
  selectedOutlet: SelectedOutlet | null;
  inletConnected?: boolean;
  inletConnectable?: boolean;
  onClose?: () => void;
  onOutletSelected?: (outlet: SelectedOutlet) => void;
  onDisconnectOutlet?: (outlet: SelectedOutlet) => void;
  onInletSelected?: (inlet: SelectedInlet) => void;
  onDisconnectInlet?: (inlet: SelectedInlet) => void;
  onDragEnd?: (drag: DragEnd) => void;
  onStatusChanged?: (status: UploadStatus) => void;
}
