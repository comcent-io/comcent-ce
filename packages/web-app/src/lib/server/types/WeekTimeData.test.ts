import { weekTimeSchema, WeekTimeData } from './WeekTimeData.js';

type WeekTime = 'WeekTime';

let testData: WeekTimeData;

describe('weekTimeSchema', () => {
  beforeEach(() => {
    testData = {
      id: 'e4ac0bfc-04ba-4c0c-af17-674f9be50804',
      type: 'WeekTime' as WeekTime,
      data: {
        timezone: 'Asia/Kolkata',
        mon: {
          include: true,
          timeSlots: [{ from: '05:00', to: '13:00' }],
        },
        tue: {
          include: true,
          timeSlots: [{ from: '09:00', to: '17:00' }],
        },
        wed: {
          include: true,
          timeSlots: [{ from: '09:00', to: '17:00' }],
        },
        thu: {
          include: false,
          timeSlots: [{ from: '09:00', to: '23:59' }],
        },
        fri: {
          include: true,
          timeSlots: [{ from: '08:00', to: '17:00' }],
        },
        sat: {
          include: false,
          timeSlots: [{ from: '09:00', to: '17:00' }],
        },
        sun: {
          include: false,
          timeSlots: [{ from: '09:00', to: '17:00' }],
        },
      },
      outlets: {
        true: 'eafe7444-ca3c-439d-9eff-55871b33e0fa',
        false: '14d6dec8-add0-4cd3-a0f9-6eda06f55fa2',
      },
      screen: {
        tx: -65,
        ty: 97,
      },
    };
  });

  it('should have valid from time', () => {
    let parsedData = weekTimeSchema.safeParse(testData);
    expect(parsedData.success).toBe(true);

    testData.data.mon.timeSlots[0].from = '24:00';
    parsedData = weekTimeSchema.safeParse(testData);
    expect(parsedData.success).toBe(false);

    testData.data.mon.timeSlots[0].from = '12:60';
    parsedData = weekTimeSchema.safeParse(testData);
    expect(parsedData.success).toBe(false);

    testData.data.mon.timeSlots[0].from = '9:05';
    parsedData = weekTimeSchema.safeParse(testData);
    expect(parsedData.success).toBe(false);

    testData.data.mon.timeSlots[0].from = '17:9';
    parsedData = weekTimeSchema.safeParse(testData);
    expect(parsedData.success).toBe(false);
  });

  it('should have valid to time', () => {
    let parsedData = weekTimeSchema.safeParse(testData);
    expect(parsedData.success).toBe(true);

    testData.data.mon.timeSlots[0].to = '24:00';
    parsedData = weekTimeSchema.safeParse(testData);
    expect(parsedData.success).toBe(false);

    testData.data.mon.timeSlots[0].to = '12:60';
    parsedData = weekTimeSchema.safeParse(testData);
    expect(parsedData.success).toBe(false);

    testData.data.mon.timeSlots[0].to = '9:05';
    parsedData = weekTimeSchema.safeParse(testData);
    expect(parsedData.success).toBe(false);

    testData.data.mon.timeSlots[0].to = '17:9';
    parsedData = weekTimeSchema.safeParse(testData);
    expect(parsedData.success).toBe(false);
  });
});
