import React, { useState } from 'react';
import { AuthProvider, useAuth } from './context/AuthContext';
import { useMessagingStore } from './stores/messagingStore';
import ConversationList from './components/MessagingUI/ConversationList';
import MessageThread from './components/MessagingUI/MessageThread';
import MessageComposer from './components/MessagingUI/MessageComposer';
import PostCreator from './components/PostCreator/PostCreator';
import FeedView from './components/Feed/FeedView';

type View = 'messaging' | 'post-creator' | 'feed';

const Shell: React.FC = () => {
  const { userId, setUserId } = useAuth();
  const apiBase = useMessagingStore((s) => s.apiBase);
  const addConversation = useMessagingStore((s) => s.addConversation);
  const setCurrentConversation = useMessagingStore((s) => s.setCurrentConversation);
  const [convInput, setConvInput] = useState('');
  const [peerId, setPeerId] = useState('');
  const [currentView, setCurrentView] = useState<View>('post-creator');

  return (
    <div style={{ padding: 16, maxWidth: 1400, margin: '0 auto' }}>
      <div style={{ marginBottom: 24 }}>
        <h2 style={{ margin: 0, marginBottom: 16 }}>Nova Social Media</h2>

        {/* Navigation Tabs */}
        <div style={{ display: 'flex', gap: 8, borderBottom: '2px solid #e0e0e0' }}>
          <button
            onClick={() => setCurrentView('post-creator')}
            style={{
              padding: '12px 24px',
              border: 'none',
              background: currentView === 'post-creator' ? '#007bff' : 'transparent',
              color: currentView === 'post-creator' ? 'white' : '#333',
              fontWeight: 600,
              cursor: 'pointer',
              borderRadius: '8px 8px 0 0',
              transition: 'all 0.2s',
            }}
          >
            Create Post
          </button>
          <button
            onClick={() => setCurrentView('messaging')}
            style={{
              padding: '12px 24px',
              border: 'none',
              background: currentView === 'messaging' ? '#007bff' : 'transparent',
              color: currentView === 'messaging' ? 'white' : '#333',
              fontWeight: 600,
              cursor: 'pointer',
              borderRadius: '8px 8px 0 0',
              transition: 'all 0.2s',
            }}
          >
            Messaging
          </button>
          <button
            onClick={() => setCurrentView('feed')}
            style={{
              padding: '12px 24px',
              border: 'none',
              background: currentView === 'feed' ? '#007bff' : 'transparent',
              color: currentView === 'feed' ? 'white' : '#333',
              fontWeight: 600,
              cursor: 'pointer',
              borderRadius: '8px 8px 0 0',
              transition: 'all 0.2s',
            }}
          >
            Feed
          </button>
        </div>
      </div>

      {/* Post Creator View */}
      {currentView === 'post-creator' && (
        <PostCreator
          onSuccess={(postId) => {
            console.log('Post created successfully:', postId);
            alert(`Post created! ID: ${postId}`);
          }}
          onError={(error) => {
            console.error('Post creation failed:', error);
          }}
        />
      )}

      {/* Messaging View */}
      {currentView === 'messaging' && (
        <div>
          <h3>Messaging (US1 Demo)</h3>
          <div style={{ display: 'flex', gap: 16, marginBottom: 16 }}>
            <div>
              <label>User ID:&nbsp;</label>
              <input value={userId ?? ''} onChange={(e) => setUserId(e.target.value || null)} placeholder="u-1" />
            </div>
            <div>
              <label>Conversation ID:&nbsp;</label>
              <input value={convInput} onChange={(e) => setConvInput(e.target.value)} placeholder="c-1 (UUID)" />
              <button onClick={() => { if (convInput) { addConversation({ id: convInput }); setConvInput(''); } }}>Add</button>
            </div>
            <div>
              <label>Peer (UUID):&nbsp;</label>
              <input value={peerId} onChange={(e) => setPeerId(e.target.value)} placeholder="peer-user-uuid" />
              <button onClick={async () => {
                if (!userId || !peerId) return;
                try {
                  const res = await fetch(`${apiBase}/conversations`, {
                    method: 'POST', headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ user_a: userId, user_b: peerId })
                  });
                  if (!res.ok) throw new Error(`HTTP ${res.status}`);
                  const data = await res.json();
                  addConversation({ id: data.id });
                  setCurrentConversation(data.id);
                  setPeerId('');
                } catch (e) { console.error(e); }
              }}>Create 1:1</button>
            </div>
          </div>
          <hr />
          <div style={{ display: 'grid', gridTemplateColumns: '240px 1fr', gap: 16 }}>
            <div>
              <h4>Conversations</h4>
              <ConversationList />
            </div>
            <div>
              <h4>Thread</h4>
              <MessageThread />
              <div style={{ marginTop: 8 }}>
                <MessageComposer />
              </div>
            </div>
          </div>
        </div>
      )}

      {/* Feed View */}
      {currentView === 'feed' && (
        <FeedView />
      )}
    </div>
  );
};

const App: React.FC = () => (
  <AuthProvider>
    <Shell />
  </AuthProvider>
);

export default App;
