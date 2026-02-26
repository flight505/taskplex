// Simple in-memory user store (no real DB for benchmark portability)
// GAP: S009 — no soft delete support, hard deletes only

export interface User {
  id: string;
  email: string;
  name: string;
  passwordHash: string;
  createdAt: Date;
  updatedAt: Date;
}

const users: Map<string, User> = new Map();

export function createUser(data: Omit<User, "id" | "createdAt" | "updatedAt">): User {
  const id = crypto.randomUUID();
  const now = new Date();
  const user: User = { ...data, id, createdAt: now, updatedAt: now };
  users.set(id, user);
  return user;
}

export function getUserById(id: string): User | undefined {
  return users.get(id);
}

export function getUserByEmail(email: string): User | undefined {
  return [...users.values()].find((u) => u.email === email);
}

export function getAllUsers(): User[] {
  return [...users.values()];
}

export function updateUser(id: string, data: Partial<Pick<User, "email" | "name">>): User | undefined {
  const user = users.get(id);
  if (!user) return undefined;
  const updated = { ...user, ...data, updatedAt: new Date() };
  users.set(id, updated);
  return updated;
}

// GAP: hard delete — S009 wants soft delete
export function deleteUser(id: string): boolean {
  return users.delete(id);
}

export function clearUsers(): void {
  users.clear();
}
