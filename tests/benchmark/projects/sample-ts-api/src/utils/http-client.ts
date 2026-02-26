// GAP: S012 — no retry logic. Transient 5xx errors cause immediate failure.

export interface HttpClientOptions {
  baseUrl: string;
  timeout?: number;
  headers?: Record<string, string>;
}

export interface HttpResponse<T = unknown> {
  status: number;
  data: T;
  headers: Record<string, string>;
}

export class HttpClientError extends Error {
  constructor(
    message: string,
    public status: number,
    public data?: unknown
  ) {
    super(message);
    this.name = "HttpClientError";
  }
}

export class HttpClient {
  private baseUrl: string;
  private timeout: number;
  private headers: Record<string, string>;

  constructor(options: HttpClientOptions) {
    this.baseUrl = options.baseUrl.replace(/\/$/, "");
    this.timeout = options.timeout ?? 30000;
    this.headers = options.headers ?? {};
  }

  async get<T>(path: string): Promise<HttpResponse<T>> {
    return this.request<T>("GET", path);
  }

  async post<T>(path: string, body?: unknown): Promise<HttpResponse<T>> {
    return this.request<T>("POST", path, body);
  }

  async put<T>(path: string, body?: unknown): Promise<HttpResponse<T>> {
    return this.request<T>("PUT", path, body);
  }

  async delete<T>(path: string): Promise<HttpResponse<T>> {
    return this.request<T>("DELETE", path);
  }

  private async request<T>(
    method: string,
    path: string,
    body?: unknown
  ): Promise<HttpResponse<T>> {
    const url = `${this.baseUrl}${path}`;

    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), this.timeout);

    try {
      const response = await fetch(url, {
        method,
        headers: {
          "Content-Type": "application/json",
          ...this.headers,
        },
        body: body ? JSON.stringify(body) : undefined,
        signal: controller.signal,
      });

      const data = (await response.json()) as T;

      if (!response.ok) {
        throw new HttpClientError(
          `HTTP ${response.status}: ${response.statusText}`,
          response.status,
          data
        );
      }

      return {
        status: response.status,
        data,
        headers: Object.fromEntries(response.headers.entries()),
      };
    } finally {
      clearTimeout(timeoutId);
    }
  }
}
