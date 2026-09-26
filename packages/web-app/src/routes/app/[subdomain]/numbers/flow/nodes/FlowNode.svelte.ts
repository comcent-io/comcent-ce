export class FlowNode {
  // Reactive, so the flow builder's components can read and edit a node's
  // data in place and every view of it updates. Subclasses narrow the type
  // with `declare data: ...`; a plain field redeclaration would replace this
  // reactive accessor with an ordinary property.

  data: any = $state();

  component: any;

  // Overridden by the node types that have outlets.
  // eslint-disable-next-line @typescript-eslint/no-unused-vars
  linkOutletToInlet(outletId: string, inletId: string): void {
    return;
  }

  updatePosition(tx: number, ty: number): void {
    if (!this.data.screen) {
      this.data.screen = {};
    }
    this.data.screen.tx = tx;
    this.data.screen.ty = ty;
  }
}
