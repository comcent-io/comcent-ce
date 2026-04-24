import { convertNumberToE164OrUs11 } from './dialUtils.js';

describe('dialUtils', () => {
  describe('convertNumberToE164OrUs11', () => {
    it('should convert properly ', () => {
      let number = convertNumberToE164OrUs11('18002211212', '+18557876543');
      expect(number).toBe('18557876543');

      number = convertNumberToE164OrUs11('+18002211212', '+18557876543');
      expect(number).toBe('+18557876543');

      number = convertNumberToE164OrUs11('18002211212', '+919845012345');
      expect(number).toBe('919845012345');

      number = convertNumberToE164OrUs11('18002211212', '919845012345');
      expect(number).toBe('919845012345');

      number = convertNumberToE164OrUs11('+18002211212', '+919845012345');
      expect(number).toBe('+919845012345');

      number = convertNumberToE164OrUs11('+18002211212', '919845012345');
      expect(number).toBe('+919845012345');

      number = convertNumberToE164OrUs11('+18002211212', '(800)-221-1212');
      expect(number).toBe('+18002211212');

      number = convertNumberToE164OrUs11('18002211212', '(800)-221-1212');
      expect(number).toBe('18002211212');
    });
  });
});
