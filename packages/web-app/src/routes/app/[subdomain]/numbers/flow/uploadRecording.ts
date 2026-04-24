import type { AudioChangePayload } from './AudioChangedPayload';

export async function uploadRecording(subdomain: string, changedAudio: AudioChangePayload) {
  try {
    const encodedFileName = encodeURIComponent(changedAudio.fileName);
    const signedUrlResponse = await fetch(
      `/api/v2/${subdomain}/uploads/get-signed-url?filename=${encodedFileName}&access=put`,
    );
    if (!signedUrlResponse.ok) {
      alert('Failed to upload play node audio file');
    }

    const { url: signedUrl } = await signedUrlResponse.json();
    const uploadResponse = await fetch(signedUrl, {
      method: 'PUT',
      body: changedAudio.audioBlob,
      headers: { 'Content-Type': changedAudio.mimeType },
    });

    if (!uploadResponse.ok) {
      alert('Failed to upload file to S3.');
    }

    return `s3://${subdomain}/playback/${changedAudio.fileName}`;
  } catch (error: any) {
    alert(`Error during the upload process: ${error}`);
    return null;
  }
}
