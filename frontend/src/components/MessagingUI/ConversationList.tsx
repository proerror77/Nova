import React from 'react';
import { useMessagingStore } from '../../stores/messagingStore';

export const ConversationList: React.FC = () => {
  const conversations = useMessagingStore((s) => s.conversations);
  const currentId = useMessagingStore((s) => s.currentConversationId);
  const setCurrent = useMessagingStore((s) => s.setCurrentConversation);

  if (conversations.length === 0) {
    return <div>No conversations</div>;
  }

  return (
    <ul>
      {conversations.map((c) => {
        const msgs = useMessagingStore.getState().messages[c.id] ?? [];
        const last = msgs[msgs.length - 1];
        return (
          <li key={c.id}>
            <button
              onClick={() => setCurrent(c.id)}
              style={{ fontWeight: currentId === c.id ? 'bold' : 'normal', display: 'block' }}
            >
              {c.name ?? c.id}
            </button>
            {last && <small style={{ opacity: 0.7 }}>last: {last.preview ?? `#${last.sequence_number}`}</small>}
          </li>
        );
      })}
    </ul>
  );
};

export default ConversationList;
