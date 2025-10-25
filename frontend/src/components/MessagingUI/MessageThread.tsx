import React, { useEffect, useRef } from 'react';
import { useMessagingStore } from '../../stores/messagingStore';
import { useAuth } from '../../context/AuthContext';

export const MessageThread: React.FC = () => {
  const currentId = useMessagingStore((s) => s.currentConversationId);
  const messages = useMessagingStore((s) =>
    currentId ? s.messages[currentId] ?? [] : []
  );
  const typing = useMessagingStore((s) => (currentId ? s.typing[currentId] ?? [] : []));
  const ref = useRef<HTMLDivElement>(null);
  const { userId } = useAuth();

  useEffect(() => {
    if (ref.current) {
      ref.current.scrollTop = ref.current.scrollHeight;
    }
  }, [messages.length]);

  if (!currentId) return <div>Select a conversation</div>;

  // Load history and connect WS when conversation changes
  useEffect(() => {
    if (!currentId || !userId) return;
    (async () => {
      await useMessagingStore.getState().loadMessages(currentId);
      useMessagingStore.getState().connectWs(currentId, userId);
    })();
    return () => useMessagingStore.getState().disconnectWs();
  }, [currentId, userId]);

  return (
    <div ref={ref} style={{ height: 300, overflowY: 'auto', border: '1px solid #eee', padding: 8 }}>
      {messages.map((m) => (
        <div key={m.id}>
          <small>#{m.sequence_number}</small> <b>{m.sender_id}</b>: <i>{m.preview ?? '(encrypted)'}</i>
        </div>
      ))}
      {typing.length > 0 && (
        <div style={{ opacity: 0.7, fontStyle: 'italic', marginTop: 4 }}>typing...</div>
      )}
    </div>
  );
};

export default MessageThread;
