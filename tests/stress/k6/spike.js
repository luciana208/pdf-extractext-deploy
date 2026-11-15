// prueba spike (modelo cerrado): 0 -> 100 vus en 10 s, 20 s sostenido, bajada en 10 s
import http from 'k6/http';
import { check } from 'k6';

const BASE_URL = __ENV.BASE_URL || 'https://extract.pdfextractext.localhost';
const FILES = (__ENV.PDF_FILES || 'liviano.pdf,mediano.pdf,pesado.pdf,graficos.pdf').split(',');

// los pdfs se cargan una vez al inicio, no en cada iteracion
const pdfs = FILES.map((name) => ({ name, data: open(`../pdfs/${name}`, 'b') }));

export const options = {
  insecureSkipTLSVerify: true,
  stages: [
    { duration: '10s', target: 100 },
    { duration: '20s', target: 100 },
    { duration: '10s', target: 0 },
  ],
  summaryTrendStats: ['avg', 'min', 'med', 'p(90)', 'p(95)', 'max'],
};

export default function () {
  const pdf = pdfs[__ITER % pdfs.length];
  const response = http.post(`${BASE_URL}/extract`, {
    file: http.file(pdf.data, pdf.name, 'application/pdf'),
  }, { timeout: '30s' });

  check(response, {
    'status 200': (r) => r.status === 200,
    'trae content y page_count': (r) => r.status === 200 && r.json('page_count') > 0,
  });
}
