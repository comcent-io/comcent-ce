export function errorResponse(message: string, status = 500) {
  return new Response(JSON.stringify({ error: message }), {
    status,
    headers: {
      'Content-Type': 'application/json',
    },
  });
}

export function redirectResponse(location: string, status = 302) {
  return new Response('', {
    status,
    headers: {
      Location: location,
    },
  });
}
