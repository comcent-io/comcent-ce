// The usernames of the org's members matching the text, for the Dial and
// Dial group blocks. An error counts as no match.
export async function searchMemberUsernames(subdomain: string, text: string): Promise<string[]> {
  try {
    const response = await fetch(`/api/v2/${subdomain}/members?search=${encodeURIComponent(text)}`);
    if (!response.ok) {
      throw new Error('Network response was not ok');
    }
    const payload = await response.json();
    return (payload.members ?? []).map((member: { username: string }) => member.username);
  } catch (error) {
    console.error('Error fetching data:', error);
    return [];
  }
}
