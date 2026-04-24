export class FlowNode {
  data: any;
  component: any;
  linkOutletToInlet(outletId: string, inletId: string): void {
    return;
  }
  updatePosition(tx: number, ty: number): void {
    console.log('updatePosition');
    if (!this.data.screen) {
      this.data.screen = {};
    }
    this.data.screen.tx = tx;
    this.data.screen.ty = ty;
  }
}
