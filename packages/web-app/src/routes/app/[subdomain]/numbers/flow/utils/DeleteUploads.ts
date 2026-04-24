export function extractFilenameFromS3Url(s3Url: string): string {
  const parts = s3Url.split('/');
  return parts[parts.length - 1]; // Returns the last segment after splitting by '/'
}

export async function deleteS3File(subdomain: string, s3URL: string) {
  const oldFileName = extractFilenameFromS3Url(s3URL);
  console.log('deleting old file', oldFileName);
  try {
    const response = await fetch(
      `/api/v2/${subdomain}/uploads?filename=${encodeURIComponent(oldFileName)}`,
      {
        method: 'DELETE',
      },
    );
    if (!response.ok) {
      console.error('Failed to delete old file.');
    }
  } catch (error) {
    console.error('Error during the delete process:', error);
  }
}

export async function deleteS3Uploads(subdomain: string, deletedNodes: any[]) {
  for (const node of deletedNodes) {
    if (node.data.type === 'Play') {
      await deleteS3File(subdomain, node.data.data.media);
    } else if (node.data.type === 'Menu') {
      await Promise.all([
        deleteS3File(subdomain, node.data.data.promptAudio),
        deleteS3File(subdomain, node.data.data.errorAudio),
      ]);
    }
  }
}
