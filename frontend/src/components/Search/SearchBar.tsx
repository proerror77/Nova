import React, { useEffect, useRef, useState } from 'react';
import { useSearchStore, type SortOrder } from '../../stores/searchStore';

interface SearchBarProps {
  conversationId: string | null;
  apiBase: string;
  token: string;
  onResultClick?: (resultId: string) => void;
}

/**
 * SearchBar component with debounced search and result display
 *
 * Features:
 * - Debounced input (300ms) to reduce API calls
 * - Full-text search with sorting options
 * - Pagination with prev/next buttons
 * - Loading and error states
 * - Result highlighting
 */
export const SearchBar: React.FC<SearchBarProps> = ({
  conversationId,
  apiBase,
  token,
  onResultClick,
}) => {
  const {
    query,
    setQuery,
    setSortBy,
    sortBy,
    results,
    total,
    hasMore,
    isLoading,
    error,
    offset,
    limit,
    search,
    nextPage,
    previousPage,
    getCurrentPage,
    getTotalPages,
    setConversationId,
    reset,
  } = useSearchStore();

  const [showResults, setShowResults] = useState(false);
  const debounceTimer = useRef<NodeJS.Timeout>();

  // Update conversation ID when prop changes
  useEffect(() => {
    setConversationId(conversationId);
  }, [conversationId, setConversationId]);

  // Debounced search handler
  useEffect(() => {
    if (debounceTimer.current) {
      clearTimeout(debounceTimer.current);
    }

    if (!query.trim()) {
      reset();
      return;
    }

    debounceTimer.current = setTimeout(() => {
      if (conversationId && query.trim()) {
        search(apiBase, token);
        setShowResults(true);
      }
    }, 300); // 300ms debounce

    return () => {
      if (debounceTimer.current) {
        clearTimeout(debounceTimer.current);
      }
    };
  }, [query, apiBase, token, conversationId, search, reset]);

  const handleInputChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    setQuery(e.target.value);
  };

  const handleSortChange = (newSort: SortOrder) => {
    setSortBy(newSort);
  };

  const handleResultClick = (resultId: string) => {
    onResultClick?.(resultId);
    setShowResults(false);
    reset();
  };

  const currentPage = getCurrentPage();
  const totalPages = getTotalPages();

  return (
    <div className="search-bar-container">
      <div className="search-input-wrapper">
        <input
          type="text"
          placeholder="Search messages..."
          value={query}
          onChange={handleInputChange}
          className="search-input"
          aria-label="Search messages"
        />
        {isLoading && <div className="search-spinner">⏳</div>}
      </div>

      {query.trim() && showResults && (
        <div className="search-results-container">
          {/* Error State */}
          {error && (
            <div className="search-error">
              <p>⚠️ {error}</p>
              <button onClick={() => search(apiBase, token)}>Retry</button>
            </div>
          )}

          {/* Sort Options */}
          {!error && total > 0 && (
            <div className="search-controls">
              <div className="sort-options">
                <label>Sort:</label>
                <select
                  value={sortBy}
                  onChange={(e) => handleSortChange(e.target.value as SortOrder)}
                  disabled={isLoading}
                >
                  <option value="recent">Most Recent</option>
                  <option value="oldest">Oldest First</option>
                  <option value="relevance">Most Relevant</option>
                </select>
              </div>
            </div>
          )}

          {/* Results or Empty State */}
          {!isLoading && results.length === 0 && !error && (
            <div className="search-empty">
              <p>No messages found for "{query}"</p>
            </div>
          )}

          {/* Results List */}
          {results.length > 0 && (
            <div className="search-results">
              {results.map((result) => (
                <SearchResultItem
                  key={result.id}
                  result={result}
                  query={query}
                  onClick={() => handleResultClick(result.id)}
                />
              ))}
            </div>
          )}

          {/* Pagination */}
          {total > 0 && (
            <div className="search-pagination">
              <button
                onClick={() => previousPage(apiBase, token)}
                disabled={offset === 0 || isLoading}
                className="pagination-btn"
              >
                ← Previous
              </button>

              <div className="pagination-info">
                <span>
                  {total === 0 ? 'No results' : `${offset + 1}-${Math.min(offset + limit, total)} of ${total}`}
                </span>
                {totalPages > 1 && <span className="page-indicator">Page {currentPage} of {totalPages}</span>}
              </div>

              <button
                onClick={() => nextPage(apiBase, token)}
                disabled={!hasMore || isLoading}
                className="pagination-btn"
              >
                Next →
              </button>
            </div>
          )}

          {/* Close Button */}
          <button
            onClick={() => setShowResults(false)}
            className="search-close-btn"
            aria-label="Close search results"
          >
            ✕
          </button>
        </div>
      )}

      <style>{`
        .search-bar-container {
          position: relative;
          width: 100%;
          max-width: 500px;
        }

        .search-input-wrapper {
          position: relative;
          display: flex;
          align-items: center;
        }

        .search-input {
          width: 100%;
          padding: 10px 15px;
          border: 1px solid #ddd;
          border-radius: 4px;
          font-size: 14px;
          font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'Roboto', 'Oxygen', 'Ubuntu', 'Cantarell', 'Fira Sans', 'Droid Sans', 'Helvetica Neue', sans-serif;
          box-sizing: border-box;
        }

        .search-input:focus {
          outline: none;
          border-color: #007bff;
          box-shadow: 0 0 0 3px rgba(0, 123, 255, 0.1);
        }

        .search-spinner {
          position: absolute;
          right: 12px;
          font-size: 18px;
        }

        .search-results-container {
          position: absolute;
          top: 100%;
          left: 0;
          right: 0;
          margin-top: 8px;
          background: white;
          border: 1px solid #ddd;
          border-radius: 4px;
          box-shadow: 0 4px 12px rgba(0, 0, 0, 0.1);
          max-height: 500px;
          overflow-y: auto;
          z-index: 1000;
        }

        .search-error {
          padding: 16px;
          background: #fff3cd;
          border-bottom: 1px solid #ddd;
          color: #856404;
          text-align: center;
        }

        .search-error button {
          margin-top: 8px;
          padding: 6px 12px;
          background: #007bff;
          color: white;
          border: none;
          border-radius: 3px;
          cursor: pointer;
          font-size: 12px;
        }

        .search-error button:hover {
          background: #0056b3;
        }

        .search-controls {
          padding: 8px 16px;
          border-bottom: 1px solid #eee;
          background: #f8f9fa;
        }

        .sort-options {
          display: flex;
          align-items: center;
          gap: 8px;
          font-size: 12px;
        }

        .sort-options label {
          font-weight: 600;
          color: #666;
        }

        .sort-options select {
          padding: 4px 8px;
          border: 1px solid #ddd;
          border-radius: 3px;
          font-size: 12px;
          background: white;
          cursor: pointer;
        }

        .sort-options select:disabled {
          opacity: 0.6;
          cursor: not-allowed;
        }

        .search-empty {
          padding: 24px 16px;
          text-align: center;
          color: #666;
          font-size: 14px;
        }

        .search-results {
          max-height: 350px;
          overflow-y: auto;
        }

        .search-result-item {
          padding: 12px 16px;
          border-bottom: 1px solid #eee;
          cursor: pointer;
          transition: background-color 0.2s;
        }

        .search-result-item:hover {
          background-color: #f5f5f5;
        }

        .search-result-item:active {
          background-color: #efefef;
        }

        .search-result-sender {
          font-size: 12px;
          color: #999;
          margin-bottom: 4px;
        }

        .search-result-content {
          font-size: 14px;
          color: #333;
          line-height: 1.4;
        }

        .search-result-date {
          font-size: 12px;
          color: #bbb;
          margin-top: 4px;
        }

        .search-result-highlight {
          background-color: #fffacd;
          padding: 0 2px;
          border-radius: 2px;
          font-weight: 600;
        }

        .search-pagination {
          padding: 12px 16px;
          border-top: 1px solid #eee;
          display: flex;
          align-items: center;
          justify-content: space-between;
          gap: 8px;
          font-size: 12px;
          background: #f8f9fa;
        }

        .pagination-btn {
          padding: 6px 12px;
          background: #007bff;
          color: white;
          border: none;
          border-radius: 3px;
          cursor: pointer;
          font-size: 12px;
          transition: background-color 0.2s;
        }

        .pagination-btn:hover:not(:disabled) {
          background: #0056b3;
        }

        .pagination-btn:disabled {
          opacity: 0.5;
          cursor: not-allowed;
        }

        .pagination-info {
          flex: 1;
          text-align: center;
          color: #666;
        }

        .page-indicator {
          display: block;
          font-size: 11px;
          color: #999;
          margin-top: 2px;
        }

        .search-close-btn {
          position: absolute;
          top: 8px;
          right: 8px;
          background: none;
          border: none;
          font-size: 18px;
          cursor: pointer;
          color: #999;
          padding: 4px;
          z-index: 1001;
        }

        .search-close-btn:hover {
          color: #333;
        }

        /* Responsive adjustments */
        @media (max-width: 768px) {
          .search-results-container {
            max-height: 400px;
          }

          .search-results {
            max-height: 250px;
          }

          .pagination-btn {
            padding: 4px 8px;
            font-size: 11px;
          }

          .search-pagination {
            flex-direction: column;
            gap: 8px;
          }

          .pagination-btn:first-child,
          .pagination-btn:last-child {
            width: 100%;
          }
        }
      `}</style>
    </div>
  );
};

// Search result item component
interface SearchResultItemProps {
  result: import('../../stores/searchStore').SearchResult;
  query: string;
  onClick: () => void;
}

const SearchResultItem: React.FC<SearchResultItemProps> = ({ result, query, onClick }) => {
  // This is a placeholder - in a real implementation, you'd fetch the message content
  // For now, we just show metadata
  const date = new Date(result.created_at).toLocaleString();

  return (
    <div className="search-result-item" onClick={onClick}>
      <div className="search-result-sender">
        Message from {result.sender_id.substring(0, 8)}... • Seq: {result.sequence_number}
      </div>
      <div className="search-result-content">
        [Message content would be displayed here]
      </div>
      <div className="search-result-date">{date}</div>
    </div>
  );
};

export default SearchBar;
