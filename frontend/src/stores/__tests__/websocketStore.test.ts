import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { useMessagingStore } from '../../stores/messagingStore';

class MockWS {
  static instances: MockWS[] = [];
  url: string;
  onopen: ((e: any) => any) | null = null;
  onclose: ((e: any) => any) | null = null;
  onerror: ((e: any) => any) | null = null;
  onmessage: ((e: any) => any) | null = null;
  constructor(url: string) {
    this.url = url;
    MockWS.instances.push(this);
    queueMicrotask(() => this.onopen?.({}));
  }
  send(_: any) {}
  close() { this.onclose?.({}); }
}

describe('WebSocket store integration', () => {
  const realWS = (global as any).WebSocket;
  beforeEach(() => {
    // @ts-ignore
    (global as any).WebSocket = MockWS as any;
    const { setState } = useMessagingStore as any;
    setState({ apiBase: 'http://localhost:8080', conversations: [], currentConversationId: null, messages: {}, typing: {} }, true);
    vi.useFakeTimers();
  });
  afterEach(() => {
    (global as any).WebSocket = realWS;
    vi.useRealTimers();
  });

  it('orders messages by sequence_number and ignores duplicates', async () => {
    const s = useMessagingStore.getState();
    s.addConversation({ id: 'c-1' });
    s.setCurrentConversation('c-1');
    // do not trigger HTTP fetch
    s.connectWs('c-1', 'u-1');
    const ws = MockWS.instances.at(-1)!;
    // send reverse order
    ws.onmessage?.({ data: JSON.stringify({ type: 'message', message: { id: 'm-2', sender_id: 'u-2', sequence_number: 2 } }) });
    ws.onmessage?.({ data: JSON.stringify({ type: 'message', message: { id: 'm-1', sender_id: 'u-2', sequence_number: 1 } }) });
    let msgs = useMessagingStore.getState().messages['c-1'];
    expect(msgs.map(m => m.sequence_number)).toEqual([1, 2]);
    // duplicate by id
    ws.onmessage?.({ data: JSON.stringify({ type: 'message', message: { id: 'm-1', sender_id: 'u-2', sequence_number: 1 } }) });
    msgs = useMessagingStore.getState().messages['c-1'];
    expect(msgs.length).toBe(2);
    // duplicate by sequence_number
    ws.onmessage?.({ data: JSON.stringify({ type: 'message', message: { id: 'm-1b', sender_id: 'u-2', sequence_number: 1 } }) });
    msgs = useMessagingStore.getState().messages['c-1'];
    expect(msgs.length).toBe(2);
  });

  it('typing indicator adds and auto-clears', async () => {
    const s = useMessagingStore.getState();
    s.addConversation({ id: 'c-1' });
    s.setCurrentConversation('c-1');
    s.connectWs('c-1', 'u-1');
    const ws = MockWS.instances.at(-1)!;
    ws.onmessage?.({ data: JSON.stringify({ type: 'typing', conversation_id: 'c-1', user_id: 'u-2' }) });
    let typing = useMessagingStore.getState().typing['c-1'] || [];
    expect(typing.includes('u-2')).toBe(true);
    vi.advanceTimersByTime(3100);
    typing = useMessagingStore.getState().typing['c-1'] || [];
    expect(typing.includes('u-2')).toBe(false);
  });
});

