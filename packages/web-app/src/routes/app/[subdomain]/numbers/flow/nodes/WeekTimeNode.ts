import { FlowNode } from './FlowNode';
import WeekTimeNodeComponent from './WeekTimeNode.svelte';
import { v4 as uuidv4 } from 'uuid';
import type { WeekTimeData } from '$lib/server/types/WeekTimeData';

export class WeekTimeNode extends FlowNode {
  data: WeekTimeData;
  component = WeekTimeNodeComponent;
  constructor(data?: WeekTimeData) {
    super();
    if (data) {
      this.data = data;
    } else {
      this.data = {
        id: uuidv4(),
        type: 'WeekTime',
        data: {
          timezone: 'UTC',
          mon: {
            include: false,
            timeSlots: [
              {
                from: '09:00',
                to: '17:00',
              },
            ],
          },
          tue: {
            include: false,
            timeSlots: [
              {
                from: '09:00',
                to: '17:00',
              },
            ],
          },
          wed: {
            include: false,
            timeSlots: [
              {
                from: '09:00',
                to: '17:00',
              },
            ],
          },
          thu: {
            include: false,
            timeSlots: [
              {
                from: '09:00',
                to: '17:00',
              },
            ],
          },
          fri: {
            include: false,
            timeSlots: [
              {
                from: '09:00',
                to: '17:00',
              },
            ],
          },
          sat: {
            include: false,
            timeSlots: [
              {
                from: '09:00',
                to: '17:00',
              },
            ],
          },
          sun: {
            include: false,
            timeSlots: [
              {
                from: '09:00',
                to: '17:00',
              },
            ],
          },
        },
        outlets: {
          true: '',
          false: '',
        },
      };
    }
  }

  linkOutletToInlet(outletId: 'true' | 'false', inletId: string) {
    this.data.outlets[outletId] = inletId;
  }
}
