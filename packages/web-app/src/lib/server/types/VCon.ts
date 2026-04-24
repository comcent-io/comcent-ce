export type VCon = {
  vcon: '0.0.1';
  uuid: string;
  created_at: Date;
  parties: Party[];
  dialog: Dialog[];
  attachments: Attachment[];
  analysis: Analysis[];
};

export type CivicAddress = {
  country?: string;
  a1?: string;
  a2?: string;
  a3?: string;
  a4?: string;
  a5?: string;
  a6?: string;
  prd?: string;
  pod?: string;
  sts?: string;
  hno?: string;
  hns?: string;
  lmk?: string;
  loc?: string;
  flr?: string;
  nam?: string;
  pc?: string;
  // RFC6848 civic address extensions can be added here if needed
};

export type Party = {
  tel?: string; // Optional TEL URL
  stir?: string; // Optional STIR PASSporT in JWS Compact Serialization form
  mailto?: string; // Optional MAILTO URL
  name?: string; // Optional free form JSON string representing the party's name
  validation?: string; // Optional label or token identifying the method of identity validation
  jCard?: unknown; // TODO: Add jCard type if needed
  gmlpos?: string; // Optional geolocation string (format as defined in PIDF-LO PIDF)
  civicaddress?: CivicAddress; // Optional Civic Address Object
  timezone?: string; // TODO: Define type for timezone if needed
};

export type DialogType = 'recording' | 'text' | 'transfer' | 'incomplete';

export type Dialog = {
  type: DialogType;
  start?: Date;
  duration?: number;
  parties?: number | number[];
  originator?: number;
  mimetype?: MimeType;
  filename?: string;
  body?: string;
  encoding?: string;
  url?: string;
  alg?: string;
  signature?: string;
  disposition?: DialogDisposition;
  transferee?: number; // Index into the parties Object array for the Transferee
  transferor?: number; // Index into the parties Object array for the Transferor
  transferTarget?: number; // Index into the parties Object array for the Transfer Target
  original?: number; // Index into the dialogs Object array for the original dialog between Transferee and Transferor
  consultation?: number; // Index into the dialogs Object array for the consultative dialog (optional)
  targetDialog?: number;
};

export type MimeType =
  | 'text/plain'
  | 'audio/x-wav'
  | 'audio/x-mp3'
  | 'audio/x-mp4'
  | 'audio/ogg'
  | 'video/x-mp4'
  | 'video/ogg'
  | 'multipart/mixed';

export type DialogDisposition =
  | 'no-answer'
  | 'congestion'
  | 'failed'
  | 'busy'
  | 'hung-up'
  | 'voicemail-no-message';

export type Attachment = {
  type?: string; // TODO: Define specific semantic types like "contract" or "presentation" if needed
  party: number; // Index into the Parties Object array for the party that contributed the attachment
  mimetype?: string; // Media type of the attached file
  filename?: string; // Optional name for the attachment file
  body?: string; // Body of the attachment (for inline attachments)
  encoding?: string; // Encoding of the attachment (for inline attachments)
  url?: string; // URL for externally referenced attachments
  alg?: string; // Algorithm used for signature verification (for externally referenced attachments)
  signature?: string; // Signature of the attachment content (for externally referenced attachments)
};

export type Analysis = {
  type: string;
  dialog?: number | number[];
  mimeType?: string;
  filename?: string;
  vendor: string;
  product?: string;
  schema?: string;
  body?: string;
  encoding?: string;
  url?: string;
  alg?: string;
  signature?: string;
};
