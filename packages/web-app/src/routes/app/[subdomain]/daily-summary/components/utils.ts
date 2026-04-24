// Remove first 6 headings and code block markers, return raw content
export function processContent(content: string): string {
  if (!content) return '';

  // Remove code block markers but keep content inside
  let lines = content.split('\n');

  // Remove code block opening markers from first line
  if (lines.length > 0) {
    lines[0] = lines[0].replace(/^```markdown\s*/i, '').replace(/^```\s*/, '');
  }

  // Remove code block closing markers from last line
  if (lines.length > 0) {
    lines[lines.length - 1] = lines[lines.length - 1].replace(/\s*```$/, '');
  }

  content = lines.join('\n');
  lines = content.split('\n');
  let headingCount = 0;
  const processedLines: string[] = [];

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    const trimmed = line.trim();

    // Skip horizontal rules (--- or ***)
    if (trimmed.match(/^[-*]{3,}$/)) {
      continue;
    }

    // Count and skip first 6 headings
    if (trimmed.startsWith('#')) {
      headingCount++;
      if (headingCount <= 6) {
        continue; // Skip first 6 headings
      }
    }

    // Keep all other content as-is
    processedLines.push(line);
  }

  return processedLines.join('\n');
}

export function formatDate(dateString: string): string {
  const date = new Date(dateString);
  return date.toLocaleDateString('en-US', {
    year: 'numeric',
    month: 'long',
    day: 'numeric',
  });
}

export function calculatePercentage(value: number, total: number): number {
  if (total === 0) return 0;
  return Math.round((value / total) * 100);
}
