export interface RecordingMetadata {
  fileName: string;
  sha512: string;
  direction: 'in' | 'both';
  fileSize: string; // in bytes
}
