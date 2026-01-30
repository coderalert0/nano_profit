import type { WireEvent } from "./types.js";

const DEFAULT_MAX_SIZE = 1000;
const DEFAULT_BATCH_SIZE = 25;

export class EventQueue {
  private items: WireEvent[] = [];
  private readonly maxSize: number;
  private readonly batchSize: number;

  constructor(maxSize?: number, batchSize?: number) {
    this.maxSize = maxSize ?? DEFAULT_MAX_SIZE;
    this.batchSize = batchSize ?? DEFAULT_BATCH_SIZE;
  }

  /** Number of events currently queued. */
  get length(): number {
    return this.items.length;
  }

  /**
   * Add an event to the queue.
   * If the queue is full, the oldest event is dropped to make room.
   */
  enqueue(event: WireEvent): void {
    if (this.items.length >= this.maxSize) {
      this.items.shift(); // drop oldest
    }
    this.items.push(event);
  }

  /**
   * Drain the queue and return the events split into batches of up to
   * `batchSize` items each.
   */
  drain(): WireEvent[][] {
    if (this.items.length === 0) return [];

    const all = this.items;
    this.items = [];

    const batches: WireEvent[][] = [];
    for (let i = 0; i < all.length; i += this.batchSize) {
      batches.push(all.slice(i, i + this.batchSize));
    }
    return batches;
  }
}
