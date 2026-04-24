import Papa from 'papaparse';
import XLSX from 'xlsx';

export function parseCSVFile(buffer: any) {
  return new Promise<{ headers: string[]; customerData: any[]; rowCount: number }>(
    (resolve, reject) => {
      const csvData = buffer.toString();
      Papa.parse(csvData, {
        header: true,
        dynamicTyping: true,
        complete: (result: any) => {
          const rowCount = result.data.length;
          const headers = Object.keys(result.data[0] || {});
          resolve({ headers, customerData: result.data, rowCount });
        },
        error: (error: any) => reject(error),
      });
    },
  );
}

export function parseXLSXFile(buffer: any) {
  const workbook = XLSX.read(buffer, { type: 'buffer' });
  const sheetName = workbook.SheetNames[0];
  const sheet = workbook.Sheets[sheetName];
  const headers = XLSX.utils.sheet_to_json(sheet, { header: 1, range: 0 })[0];
  const customerData = XLSX.utils.sheet_to_json(sheet);
  const rowCount = customerData.length;

  return {
    headers,
    customerData,
    rowCount,
  };
}
