// data.results.channels[0].alternatives[0].paragraphs

export type DeepgramResult = {
  results: {
    channels: [
      {
        alternatives: [
          {
            paragraphs: {
              paragraphs: [
                {
                  sentences: {
                    text: string;
                    start: number;
                  }[];
                },
              ];
            };
          },
        ];
      },
    ];
  };
};
