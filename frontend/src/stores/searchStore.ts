import { create } from 'zustand';

export type SearchResult = {
  id: string;
  sender_id: string;
  sequence_number: number;
  created_at: string;
};

export type SortOrder = 'recent' | 'oldest' | 'relevance';

export interface SearchState {
  // Search configuration
  query: string;
  limit: number;
  offset: number;
  sortBy: SortOrder;

  // Results
  results: SearchResult[];
  total: number;
  hasMore: boolean;
  isLoading: boolean;
  error: string | null;

  // Current conversation
  conversationId: string | null;

  // Actions
  setQuery: (query: string) => void;
  setSortBy: (sort: SortOrder) => void;
  setConversationId: (id: string | null) => void;

  // Search operations
  search: (apiBase: string, token: string) => Promise<void>;
  nextPage: (apiBase: string, token: string) => Promise<void>;
  previousPage: (apiBase: string, token: string) => Promise<void>;
  reset: () => void;

  // Utility
  getCurrentPage: () => number;
  getTotalPages: () => number;
}

export const useSearchStore = create<SearchState>((set, get) => ({
  // Initial state
  query: '',
  limit: 20,
  offset: 0,
  sortBy: 'recent',

  results: [],
  total: 0,
  hasMore: false,
  isLoading: false,
  error: null,

  conversationId: null,

  // Actions
  setQuery: (query) => set({ query, offset: 0 }),
  setSortBy: (sortBy) => set({ sortBy, offset: 0 }),
  setConversationId: (conversationId) => set({ conversationId, results: [], total: 0, offset: 0 }),

  // Search implementation
  search: async (apiBase: string, token: string) => {
    const state = get();

    if (!state.conversationId || !state.query) {
      set({ error: 'Conversation ID and query are required' });
      return;
    }

    set({ isLoading: true, error: null });

    try {
      const params = new URLSearchParams({
        q: state.query,
        limit: state.limit.toString(),
        offset: state.offset.toString(),
        sort_by: state.sortBy,
      });

      const response = await fetch(
        `${apiBase}/conversations/${state.conversationId}/messages/search?${params}`,
        {
          headers: {
            'Authorization': `Bearer ${token}`,
            'Content-Type': 'application/json',
          },
        }
      );

      if (!response.ok) {
        throw new Error(`HTTP ${response.status}: Search failed`);
      }

      const data = await response.json();

      set({
        results: data.data,
        total: data.total,
        hasMore: data.has_more,
        isLoading: false,
      });
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Search failed';
      set({
        error: errorMessage,
        isLoading: false,
        results: [],
        total: 0,
        hasMore: false,
      });
    }
  },

  // Pagination
  nextPage: async (apiBase: string, token: string) => {
    const state = get();
    if (state.hasMore) {
      set({ offset: state.offset + state.limit });
      // Execute search with new offset
      const newState = get();
      await newState.search(apiBase, token);
    }
  },

  previousPage: async (apiBase: string, token: string) => {
    const state = get();
    if (state.offset > 0) {
      set({ offset: Math.max(0, state.offset - state.limit) });
      // Execute search with new offset
      const newState = get();
      await newState.search(apiBase, token);
    }
  },

  reset: () => set({
    query: '',
    offset: 0,
    results: [],
    total: 0,
    hasMore: false,
    isLoading: false,
    error: null,
  }),

  // Utilities
  getCurrentPage: () => {
    const state = get();
    return Math.floor(state.offset / state.limit) + 1;
  },

  getTotalPages: () => {
    const state = get();
    return Math.ceil(state.total / state.limit);
  },
}));
