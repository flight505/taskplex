// Simple CRUD order management — GAP: S023 wants this refactored to event sourcing

export interface OrderItem {
  productId: string;
  name: string;
  quantity: number;
  price: number;
}

export interface Order {
  id: string;
  userId: string;
  items: OrderItem[];
  status: "draft" | "submitted" | "cancelled";
  total: number;
  createdAt: Date;
  updatedAt: Date;
}

const orders: Map<string, Order> = new Map();

function calculateTotal(items: OrderItem[]): number {
  return items.reduce((sum, item) => sum + item.price * item.quantity, 0);
}

export function createOrder(userId: string): Order {
  const id = crypto.randomUUID();
  const now = new Date();
  const order: Order = {
    id,
    userId,
    items: [],
    status: "draft",
    total: 0,
    createdAt: now,
    updatedAt: now,
  };
  orders.set(id, order);
  return order;
}

export function addItem(orderId: string, item: OrderItem): Order | undefined {
  const order = orders.get(orderId);
  if (!order || order.status !== "draft") return undefined;
  order.items.push(item);
  order.total = calculateTotal(order.items);
  order.updatedAt = new Date();
  return order;
}

export function removeItem(orderId: string, productId: string): Order | undefined {
  const order = orders.get(orderId);
  if (!order || order.status !== "draft") return undefined;
  order.items = order.items.filter((i) => i.productId !== productId);
  order.total = calculateTotal(order.items);
  order.updatedAt = new Date();
  return order;
}

export function submitOrder(orderId: string): Order | undefined {
  const order = orders.get(orderId);
  if (!order || order.status !== "draft" || order.items.length === 0) return undefined;
  order.status = "submitted";
  order.updatedAt = new Date();
  return order;
}

export function cancelOrder(orderId: string): Order | undefined {
  const order = orders.get(orderId);
  if (!order || order.status === "cancelled") return undefined;
  order.status = "cancelled";
  order.updatedAt = new Date();
  return order;
}

export function getOrderById(id: string): Order | undefined {
  return orders.get(id);
}

export function getOrdersByUser(userId: string): Order[] {
  return [...orders.values()].filter((o) => o.userId === userId);
}

export function clearOrders(): void {
  orders.clear();
}
