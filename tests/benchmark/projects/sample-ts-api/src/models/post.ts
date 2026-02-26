// Simple in-memory post store

export interface Post {
  id: string;
  title: string;
  body: string;
  authorId: string;
  createdAt: Date;
  updatedAt: Date;
}

const posts: Map<string, Post> = new Map();

export function createPost(data: Omit<Post, "id" | "createdAt" | "updatedAt">): Post {
  const id = crypto.randomUUID();
  const now = new Date();
  const post: Post = { ...data, id, createdAt: now, updatedAt: now };
  posts.set(id, post);
  return post;
}

export function getPostById(id: string): Post | undefined {
  return posts.get(id);
}

export function getAllPosts(): Post[] {
  return [...posts.values()];
}

export function getPostsByAuthor(authorId: string): Post[] {
  return [...posts.values()].filter((p) => p.authorId === authorId);
}

export function updatePost(
  id: string,
  data: Partial<Pick<Post, "title" | "body">>
): Post | undefined {
  const post = posts.get(id);
  if (!post) return undefined;
  const updated = { ...post, ...data, updatedAt: new Date() };
  posts.set(id, updated);
  return updated;
}

export function deletePost(id: string): boolean {
  return posts.delete(id);
}

export function clearPosts(): void {
  posts.clear();
}
