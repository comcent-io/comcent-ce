export type Address = {
  name: string;
  address: string;
};

export type CallReceivedData = {
  from: Address;
  to: Address;
  paths: {
    type: string;
    address: string;
    name: string;
  }[];
};

export type DialerWidgetDelegate = {
  onCallReceived?: (data: CallReceivedData) => void;
  onOutboundNumberChanged?: (outboundAddress: Address) => void;
  onTokenExpired?: () => void;
};
