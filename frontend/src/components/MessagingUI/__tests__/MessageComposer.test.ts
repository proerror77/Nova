import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { useMessagingStore } from '../../../stores/messagingStore';

describe('MessageComposer flow (store-based)', () => {
  const original = global.fetch;
  beforeEach(() => {
    // @ts-ignore
    global.fetch = vi.fn(async (input: RequestInfo, init?: RequestInit) => {
      const url = String(input);
      if (url.includes('/conversations/') && url.endsWith('/messages') && init?.method === 'POST') {
        return new Response(JSON.stringify({ id: 'm-1', sequence_number: 1 }), { status: 200 });
      }
      if (url.includes('/conversations/') && url.includes('/messages') && (!init || init.method === 'GET')) {
        return new Response(JSON.stringify([]), { status: 200 });
      }
      return new Response('not found', { status: 404 });
    });
    // reset store
    const { setState } = useMessagingStore as any;
    setState({ conversations: [{ id: 'c-1' }], currentConversationId: 'c-1', messages: {} }, true);
  });
  afterEach(() => { global.fetch = original; });

  it('sends message and updates store', async () => {
    const s = useMessagingStore.getState();
    await s.sendMessage('c-1', 'u-1', 'hello');
    const messages = useMessagingStore.getState().messages['c-1'];
    expect(messages).toBeTruthy();
    expect(messages!.length).toBe(1);
    expect(messages![0].preview).toBe('hello');
  });
});

