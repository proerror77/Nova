import React, { useCallback, useRef, useState } from 'react';
import { useMessagingStore } from '../../stores/messagingStore';
import { useAuth } from '../../context/AuthContext';

export const MessageComposer: React.FC = () => {
  const { userId } = useAuth();
  const currentConversationId = useMessagingStore((s) => s.currentConversationId);
  const sendMessage = useMessagingStore((s) => s.sendMessage);
  const [text, setText] = useState('');
  const typingTs = useRef<number>(0);

  const onSend = useCallback(async () => {
    if (!currentConversationId || !userId || !text.trim()) return;
    await sendMessage(currentConversationId, userId, text);
    setText('');
  }, [currentConversationId, userId, text, sendMessage]);

  return (
    <div style={{ display: 'flex', gap: 8 }}>
      <input
        aria-label="message-input"
        value={text}
        onChange={(e) => {
          const val = e.target.value;
          setText(val);
          // Simple throttle to send typing at most every 1s
          const now = Date.now();
          if (currentConversationId && userId && now - typingTs.current > 1000) {
            typingTs.current = now;
            useMessagingStore.getState().sendTyping(currentConversationId, userId);
          }
        }}
        onKeyDown={(e) => {
          if (e.key === 'Enter') onSend();
        }}
        style={{ flex: 1 }}
        placeholder="Type a message"
      />
      <button aria-label="send-button" onClick={onSend} disabled={!currentConversationId}>Send</button>
    </div>
  );
};

export default MessageComposer;
