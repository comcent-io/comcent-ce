export interface DailySummary {
  id: string;
  date: string;
  executiveSummary: string;
  totalPromisesCreated: number;
  totalPromisesClosed: number;
}

export interface SentimentCounts {
  positive: number;
  negative: number;
  neutral: number;
}
