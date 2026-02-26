// GAP: S007 — placeholder for typed config errors (story will add Zod + custom error classes)

export class ConfigError extends Error {
  constructor(
    message: string,
    public readonly field: string,
  ) {
    super(message);
    this.name = "ConfigError";
  }
}

export class MissingConfigError extends ConfigError {
  constructor(field: string) {
    super(`Missing required configuration: ${field}`, field);
    this.name = "MissingConfigError";
  }
}

export class InvalidConfigError extends ConfigError {
  constructor(field: string, expected: string, received: string) {
    super(
      `Invalid configuration for ${field}: expected ${expected}, received ${received}`,
      field,
    );
    this.name = "InvalidConfigError";
  }
}
