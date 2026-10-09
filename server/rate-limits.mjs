export class LimitError extends Error {
  constructor(status) {
    super(status === 429 ? 'Слишком много запросов. Повторите через минуту.' : 'Защита сервера временно недоступна. Попробуйте позже.');
    this.status = status;
  }
}

// Bindings are required in deployment, while isolated unit fixtures can omit them.
export async function enforceLimit(env, binding, key) {
  if (!env[binding] && env.RATE_LIMIT_ENABLED !== 'true') return;
  try {
    if (!env[binding]) throw new LimitError(503);
    const result = await env[binding].limit({key});
    if (result.success === false) throw new LimitError(429);
    if (result.success !== true) throw new LimitError(503);
  } catch (error) {
    throw error instanceof LimitError ? error : new LimitError(503);
  }
}

export function limitResponse(error) {
  const known = error instanceof LimitError ? error : new LimitError(503);
  return Response.json({error:known.message,retry_after:60}, {
    status:known.status,headers:{'Retry-After':'60','Cache-Control':'no-store'},
  });
}
