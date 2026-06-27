#!/usr/bin/env node
const puppeteer = require('puppeteer-core');
const path = require('path');

(async () => {
  const browser = await puppeteer.launch({
    executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    headless: 'new',
  });

  const docs = [
    { html: 'onepager.html', pdf: 'JBA_HoopsConnect_OnePager.pdf', pages: '1' },
    { html: 'featureguide.html', pdf: 'JBA_HoopsConnect_FeatureGuide.pdf', pages: '3' },
  ];

  for (const doc of docs) {
    const page = await browser.newPage();
    const filePath = path.join(__dirname, doc.html);
    await page.goto(`file://${filePath}`, { waitUntil: 'networkidle0', timeout: 30000 });
    // Wait for fonts to load
    await page.evaluateHandle('document.fonts.ready');
    await page.pdf({
      path: path.join(__dirname, doc.pdf),
      format: 'A4',
      printBackground: true,
      margin: { top: 0, right: 0, bottom: 0, left: 0 },
    });
    console.log(`Generated: ${doc.pdf} (${doc.pages} page${doc.pages > 1 ? 's' : ''})`);
    await page.close();
  }

  await browser.close();
  console.log('\nDone! PDFs saved to docs/ folder.');
})();
