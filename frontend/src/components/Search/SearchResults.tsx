import React, { useEffect } from 'react';
import { useSearchStore } from '../../stores/searchStore';

interface SearchResultsProps {
  conversationId: string | null;
  apiBase: string;
  token: string;
  onMessageSelect?: (messageId: string) => void;
}

/**
 * SearchResults component for displaying full-text search results
 * with pagination, sorting, and metadata
 */
export const SearchResults: React.FC<SearchResultsProps> = ({
  conversationId,
  apiBase,
  token,
  onMessageSelect,
}) => {
  const {
    query,
    results,
    total,
    hasMore,
    isLoading,
    error,
    offset,
    limit,
    sortBy,
    setSortBy,
    nextPage,
    previousPage,
    search,
    getCurrentPage,
    getTotalPages,
  } = useSearchStore();

  if (!query.trim()) {
    return (
      <div className="search-results-empty-state">
        <h3>Search Messages</h3>
        <p>Use the search bar to find messages in this conversation</p>
      </div>
    );
  }

  const currentPage = getCurrentPage();
  const totalPages = getTotalPages();

  return (
    <div className="search-results-page">
      {/* Header */}
      <div className="search-results-header">
        <h2>Search Results</h2>
        <p className="search-query">
          Searching for: <strong>"{query}"</strong>
          {total > 0 && <span className="result-count"> ({total} results)</span>}
        </p>
      </div>

      {/* Controls */}
      {total > 0 && (
        <div className="search-results-controls">
          <div className="sort-control">
            <label htmlFor="sort-select">Sort by:</label>
            <select
              id="sort-select"
              value={sortBy}
              onChange={(e) => setSortBy(e.target.value as any)}
              disabled={isLoading}
            >
              <option value="recent">Most Recent</option>
              <option value="oldest">Oldest First</option>
              <option value="relevance">Most Relevant</option>
            </select>
          </div>

          {totalPages > 1 && (
            <div className="pagination-summary">
              Page {currentPage} of {totalPages}
            </div>
          )}
        </div>
      )}

      {/* Loading State */}
      {isLoading && (
        <div className="search-results-loading">
          <div className="spinner"></div>
          <p>Searching...</p>
        </div>
      )}

      {/* Error State */}
      {error && !isLoading && (
        <div className="search-results-error">
          <h3>⚠️ Search Error</h3>
          <p>{error}</p>
          <button
            onClick={() => search(apiBase, token)}
            className="retry-button"
          >
            Retry Search
          </button>
        </div>
      )}

      {/* No Results */}
      {!isLoading && !error && total === 0 && (
        <div className="search-results-no-results">
          <h3>No Results Found</h3>
          <p>Try different search terms or sort options</p>
        </div>
      )}

      {/* Results List */}
      {!isLoading && !error && results.length > 0 && (
        <>
          <div className="search-results-list">
            {results.map((result, index) => (
              <SearchResultRow
                key={result.id}
                result={result}
                index={offset + index + 1}
                query={query}
                onClick={() => onMessageSelect?.(result.id)}
              />
            ))}
          </div>

          {/* Pagination Controls */}
          {totalPages > 1 && (
            <div className="search-results-pagination">
              <button
                onClick={() => previousPage(apiBase, token)}
                disabled={offset === 0 || isLoading}
                className="pagination-button"
              >
                ← Previous Page
              </button>

              <div className="pagination-display">
                <span>
                  Showing {offset + 1}-{Math.min(offset + limit, total)} of {total} results
                </span>
              </div>

              <button
                onClick={() => nextPage(apiBase, token)}
                disabled={!hasMore || isLoading}
                className="pagination-button"
              >
                Next Page →
              </button>
            </div>
          )}
        </>
      )}

      <style>{`
        .search-results-page {
          width: 100%;
          max-width: 800px;
          margin: 0 auto;
          padding: 20px;
        }

        .search-results-empty-state {
          text-align: center;
          padding: 40px 20px;
          color: #666;
        }

        .search-results-empty-state h3 {
          margin: 0 0 10px 0;
          font-size: 18px;
          color: #333;
        }

        .search-results-header {
          margin-bottom: 24px;
        }

        .search-results-header h2 {
          margin: 0 0 8px 0;
          font-size: 24px;
          color: #333;
        }

        .search-query {
          margin: 0;
          font-size: 14px;
          color: #666;
        }

        .search-query strong {
          color: #007bff;
        }

        .result-count {
          color: #999;
          font-weight: normal;
        }

        .search-results-controls {
          display: flex;
          justify-content: space-between;
          align-items: center;
          padding: 12px;
          background: #f8f9fa;
          border-radius: 4px;
          margin-bottom: 20px;
          gap: 12px;
        }

        .sort-control {
          display: flex;
          align-items: center;
          gap: 8px;
        }

        .sort-control label {
          font-size: 13px;
          font-weight: 600;
          color: #333;
        }

        .sort-control select {
          padding: 6px 10px;
          border: 1px solid #ddd;
          border-radius: 3px;
          font-size: 13px;
          background: white;
          cursor: pointer;
        }

        .sort-control select:disabled {
          opacity: 0.6;
          cursor: not-allowed;
        }

        .pagination-summary {
          font-size: 13px;
          color: #666;
          font-weight: 500;
        }

        .search-results-loading {
          text-align: center;
          padding: 40px 20px;
        }

        .spinner {
          display: inline-block;
          width: 40px;
          height: 40px;
          border: 4px solid #f0f0f0;
          border-top: 4px solid #007bff;
          border-radius: 50%;
          animation: spin 0.8s linear infinite;
          margin-bottom: 16px;
        }

        @keyframes spin {
          0% { transform: rotate(0deg); }
          100% { transform: rotate(360deg); }
        }

        .search-results-loading p {
          margin: 0;
          color: #666;
          font-size: 14px;
        }

        .search-results-error {
          padding: 20px;
          background: #fff3cd;
          border: 1px solid #ffc107;
          border-radius: 4px;
          color: #856404;
          margin: 20px 0;
        }

        .search-results-error h3 {
          margin: 0 0 10px 0;
          font-size: 16px;
        }

        .search-results-error p {
          margin: 0 0 12px 0;
          font-size: 14px;
        }

        .retry-button {
          padding: 8px 16px;
          background: #007bff;
          color: white;
          border: none;
          border-radius: 3px;
          cursor: pointer;
          font-size: 14px;
          font-weight: 500;
        }

        .retry-button:hover {
          background: #0056b3;
        }

        .search-results-no-results {
          text-align: center;
          padding: 40px 20px;
          color: #666;
        }

        .search-results-no-results h3 {
          margin: 0 0 10px 0;
          font-size: 18px;
          color: #333;
        }

        .search-results-no-results p {
          margin: 0;
          font-size: 14px;
        }

        .search-results-list {
          list-style: none;
          padding: 0;
          margin: 0;
          border: 1px solid #ddd;
          border-radius: 4px;
          overflow: hidden;
          margin-bottom: 20px;
        }

        .search-result-row {
          padding: 16px;
          border-bottom: 1px solid #eee;
          cursor: pointer;
          transition: background-color 0.15s;
        }

        .search-result-row:last-child {
          border-bottom: none;
        }

        .search-result-row:hover {
          background-color: #f5f5f5;
        }

        .search-result-row:active {
          background-color: #efefef;
        }

        .search-result-number {
          display: inline-block;
          width: 24px;
          height: 24px;
          background: #007bff;
          color: white;
          border-radius: 50%;
          text-align: center;
          line-height: 24px;
          font-size: 12px;
          font-weight: 600;
          margin-right: 12px;
        }

        .search-result-header {
          display: flex;
          align-items: center;
          margin-bottom: 8px;
          font-size: 13px;
          color: #999;
        }

        .search-result-sender {
          font-weight: 500;
          color: #333;
        }

        .search-result-time {
          margin-left: auto;
        }

        .search-result-content {
          font-size: 14px;
          color: #333;
          line-height: 1.5;
          margin-bottom: 8px;
        }

        .search-result-metadata {
          display: flex;
          gap: 16px;
          font-size: 12px;
          color: #999;
        }

        .search-results-pagination {
          display: flex;
          justify-content: space-between;
          align-items: center;
          padding: 16px 0;
          gap: 12px;
        }

        .pagination-button {
          padding: 10px 16px;
          background: #007bff;
          color: white;
          border: none;
          border-radius: 4px;
          cursor: pointer;
          font-size: 14px;
          font-weight: 500;
          transition: background-color 0.2s;
        }

        .pagination-button:hover:not(:disabled) {
          background: #0056b3;
        }

        .pagination-button:disabled {
          opacity: 0.5;
          cursor: not-allowed;
        }

        .pagination-display {
          flex: 1;
          text-align: center;
          font-size: 13px;
          color: #666;
        }

        /* Responsive adjustments */
        @media (max-width: 768px) {
          .search-results-page {
            padding: 12px;
          }

          .search-results-controls {
            flex-direction: column;
            align-items: flex-start;
          }

          .search-results-pagination {
            flex-direction: column;
          }

          .pagination-button {
            width: 100%;
          }

          .sort-control {
            width: 100%;
          }

          .sort-control select {
            flex: 1;
          }
        }
      `}</style>
    </div>
  );
};

interface SearchResultRowProps {
  result: import('../../stores/searchStore').SearchResult;
  index: number;
  query: string;
  onClick: () => void;
}

const SearchResultRow: React.FC<SearchResultRowProps> = ({
  result,
  index,
  query,
  onClick,
}) => {
  const date = new Date(result.created_at);
  const dateStr = date.toLocaleDateString();
  const timeStr = date.toLocaleTimeString();

  // In a real implementation, you'd fetch and display the actual message content
  // For now, we show metadata
  const senderDisplay = result.sender_id.substring(0, 8);

  return (
    <div className="search-result-row" onClick={onClick}>
      <div className="search-result-header">
        <span className="search-result-number">{index}</span>
        <span className="search-result-sender">From {senderDisplay}...</span>
        <span className="search-result-time">{dateStr} {timeStr}</span>
      </div>
      <div className="search-result-content">
        [Message content would be fetched and displayed here]
      </div>
      <div className="search-result-metadata">
        <span>Sequence: {result.sequence_number}</span>
        <span>ID: {result.id.substring(0, 8)}...</span>
      </div>
    </div>
  );
};

export default SearchResults;
