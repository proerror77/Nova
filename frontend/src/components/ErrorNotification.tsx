/**
 * Error Notification Component
 * Displays error messages to users with auto-dismissal and recovery actions
 */

import React, { useState } from 'react';
import { useErrors, isErrorRecoverable, getErrorRecoveryAction } from '../services/api/errorStore';
import type { ErrorNotification as ErrorNotificationType } from '../services/api/errorStore';

interface ErrorNotificationItemProps extends ErrorNotificationType {
  onDismiss: (id: string) => void;
  onRetry?: () => void;
}

/**
 * Error icon mapping for accessibility
 */
const ERROR_ICON_MAP: Record<string, string> = {
  NETWORK_ERROR: '🌐',
  TIMEOUT: '⏱️',
  UNAUTHORIZED: '🔐',
  FORBIDDEN: '🚫',
  BAD_REQUEST: '❌',
  VALIDATION_ERROR: '⚠️',
  SERVER_ERROR: '💥',
  SERVICE_UNAVAILABLE: '⚠️',
  NOT_FOUND: '❓',
  CONFLICT: '⚔️',
  UNKNOWN_ERROR: '❓',
  ABORT_ERROR: '⛔',
};

/**
 * ErrorNotification Component - displays single error
 */
function ErrorNotificationItem({
  id,
  error,
  message,
  dismissed,
  onDismiss,
  onRetry,
}: ErrorNotificationItemProps) {
  const [isRemoving, setIsRemoving] = useState(false);

  if (dismissed) {
    return null;
  }

  const isRecoverable = isErrorRecoverable(error);
  const recovery = getErrorRecoveryAction(error);
  const iconEmoji = ERROR_ICON_MAP[error.type] || '⚠️';

  const handleDismiss = () => {
    setIsRemoving(true);
    setTimeout(() => {
      onDismiss(id);
    }, 300); // Match animation duration
  };

  return (
    <div
      className={`nova-error-notification nova-error-${error.type.toLowerCase()} ${isRemoving ? 'nova-error-removing' : ''}`}
      role="alert"
      aria-live="polite"
      aria-atomic="true"
    >
      <div className="nova-error-content">
        <div className="nova-error-header">
          <span className="nova-error-icon" aria-hidden="false" role="img">
            {iconEmoji}
          </span>
          <span className="nova-error-title">Error: {error.type}</span>
          <button
            className="nova-error-close"
            onClick={handleDismiss}
            aria-label={`Dismiss ${error.type} error`}
            type="button"
          >
            ✕
          </button>
        </div>

        <p className="nova-error-message">{message}</p>

        {error.details && (
          <p className="nova-error-details">{error.details}</p>
        )}

        <div className="nova-error-actions">
          {isRecoverable && onRetry && (
            <button
              className="nova-error-button nova-error-button-retry"
              onClick={onRetry}
              type="button"
              aria-label="Retry operation"
            >
              Retry
            </button>
          )}

          {recovery && (
            <button
              className="nova-error-button nova-error-button-action"
              onClick={() => {
                recovery.action();
                handleDismiss();
              }}
              type="button"
              aria-label={recovery.label}
            >
              {recovery.label}
            </button>
          )}

          <button
            className="nova-error-button nova-error-button-dismiss"
            onClick={handleDismiss}
            type="button"
            aria-label="Dismiss notification"
          >
            Dismiss
          </button>
        </div>
      </div>
    </div>
  );
}

export interface ErrorNotificationContainerProps {
  className?: string;
  maxNotifications?: number;
}

/**
 * ErrorNotificationContainer - displays all active error notifications
 */
export function ErrorNotificationContainer({
  className = '',
  maxNotifications = 5,
}: ErrorNotificationContainerProps) {
  const { errors, dismissError } = useErrors();
  const displayErrors = errors.slice(-maxNotifications);

  if (displayErrors.length === 0) {
    return null;
  }

  return (
    <div className={`nova-error-container ${className}`} role="region" aria-label="Error notifications">
      {displayErrors.map((notification) => (
        <ErrorNotificationItem
          key={notification.id}
          {...notification}
          onDismiss={dismissError}
          onRetry={undefined} // Retry is handled by automatic retry mechanism
        />
      ))}
    </div>
  );
}

/**
 * CSS Styles for error notifications
 */
export const errorNotificationStyles = `
/* Error Notification Container */
.nova-error-container {
  position: fixed;
  top: 20px;
  right: 20px;
  z-index: 9999;
  max-width: 400px;
  pointer-events: none;
}

.nova-error-notification {
  background: white;
  border: 1px solid #e5e7eb;
  border-radius: 8px;
  box-shadow: 0 10px 15px -3px rgba(0, 0, 0, 0.1);
  margin-bottom: 12px;
  pointer-events: auto;
  animation: slideIn 300ms ease-out;
}

.nova-error-notification.nova-error-removing {
  animation: slideOut 300ms ease-in forwards;
}

/* Error Type Colors */
.nova-error-network_error {
  border-left: 4px solid #f59e0b;
}

.nova-error-timeout {
  border-left: 4px solid #f59e0b;
}

.nova-error-unauthorized {
  border-left: 4px solid #dc2626;
}

.nova-error-forbidden {
  border-left: 4px solid #dc2626;
}

.nova-error-bad_request,
.nova-error-validation_error {
  border-left: 4px solid #f97316;
}

.nova-error-server_error,
.nova-error-service_unavailable {
  border-left: 4px solid #dc2626;
}

.nova-error-not_found {
  border-left: 4px solid #8b5cf6;
}

.nova-error-conflict {
  border-left: 4px solid #ec4899;
}

/* Error Content */
.nova-error-content {
  padding: 16px;
}

.nova-error-header {
  display: flex;
  align-items: center;
  gap: 12px;
  margin-bottom: 8px;
}

.nova-error-icon {
  font-size: 20px;
  flex-shrink: 0;
}

.nova-error-title {
  font-weight: 600;
  color: #1f2937;
  flex: 1;
  font-size: 14px;
}

.nova-error-close {
  background: none;
  border: none;
  padding: 4px 8px;
  cursor: pointer;
  color: #6b7280;
  font-size: 18px;
  transition: color 200ms;
  border-radius: 4px;
  flex-shrink: 0;
}

.nova-error-close:hover {
  color: #1f2937;
  background: #f3f4f6;
}

.nova-error-close:focus {
  outline: 2px solid #3b82f6;
  outline-offset: 2px;
}

.nova-error-message {
  margin: 0 0 8px 0;
  color: #374151;
  font-size: 14px;
  line-height: 1.5;
}

.nova-error-details {
  margin: 8px 0;
  color: #6b7280;
  font-size: 12px;
  line-height: 1.5;
  font-family: monospace;
  background: #f9fafb;
  padding: 8px;
  border-radius: 4px;
  word-break: break-word;
}

/* Error Actions */
.nova-error-actions {
  display: flex;
  gap: 8px;
  margin-top: 12px;
  justify-content: flex-end;
}

.nova-error-button {
  padding: 6px 12px;
  border: none;
  border-radius: 4px;
  font-size: 12px;
  font-weight: 500;
  cursor: pointer;
  transition: all 200ms;
  white-space: nowrap;
}

.nova-error-button:focus {
  outline: 2px solid #3b82f6;
  outline-offset: 2px;
}

.nova-error-button-retry {
  background: #3b82f6;
  color: white;
}

.nova-error-button-retry:hover {
  background: #2563eb;
}

.nova-error-button-action {
  background: #10b981;
  color: white;
}

.nova-error-button-action:hover {
  background: #059669;
}

.nova-error-button-dismiss {
  background: #e5e7eb;
  color: #374151;
}

.nova-error-button-dismiss:hover {
  background: #d1d5db;
}

/* Animations */
@keyframes slideIn {
  from {
    transform: translateX(400px);
    opacity: 0;
  }
  to {
    transform: translateX(0);
    opacity: 1;
  }
}

@keyframes slideOut {
  from {
    transform: translateX(0);
    opacity: 1;
  }
  to {
    transform: translateX(400px);
    opacity: 0;
  }
}

/* Responsive */
@media (max-width: 640px) {
  .nova-error-container {
    left: 20px;
    right: 20px;
    max-width: none;
  }

  .nova-error-notification {
    margin-bottom: 8px;
  }

  .nova-error-content {
    padding: 12px;
  }

  .nova-error-actions {
    flex-direction: column;
  }

  .nova-error-button {
    width: 100%;
  }
}`;
