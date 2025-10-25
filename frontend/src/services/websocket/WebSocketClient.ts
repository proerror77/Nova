export type WsHandlers = {
  onMessage?: (payload: any) => void;
  onTyping?: (conversationId: string, userId: string) => void;
  onOpen?: () => void;
  onClose?: () => void;
  onError?: (err: any) => void;
};

export class WebSocketClient {
  private ws?: WebSocket;
  private handlers: WsHandlers;
  private url: string;

  constructor(url: string, handlers: WsHandlers = {}) {
    this.url = url;
    this.handlers = handlers;
  }

  connect() {
    this.ws = new WebSocket(this.url);
    this.ws.onopen = () => this.handlers.onOpen?.();
    this.ws.onclose = () => this.handlers.onClose?.();
    this.ws.onerror = (e) => this.handlers.onError?.(e);
    this.ws.onmessage = (e) => {
      try {
        const data = JSON.parse(e.data as string);
        if (data?.type === 'typing') {
          this.handlers.onTyping?.(data.conversation_id, data.user_id);
        } else if (data?.type === 'message') {
          this.handlers.onMessage?.(data);
        }
      } catch (_) {
        // ignore
      }
    };
  }

  sendTyping(conversationId: string, userId: string) {
    this.ws?.send(
      JSON.stringify({ type: 'typing', conversation_id: conversationId, user_id: userId })
    );
  }

  close() {
    try { this.ws?.close(); } catch {}
    this.ws = undefined;
  }
}
