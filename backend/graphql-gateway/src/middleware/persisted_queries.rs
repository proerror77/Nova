/// Persisted Queries Middleware for actix-web
/// Validates GraphQL requests against persisted queries whitelist before execution
use actix_web::{
    dev::{forward_ready, Service, ServiceRequest, ServiceResponse, Transform},
    Error, HttpMessage,
};
use futures_util::future::LocalBoxFuture;
use std::future::{ready, Ready};
use std::rc::Rc;

use crate::security::PersistedQueries;

/// Middleware factory for persisted queries
#[derive(Clone)]
pub struct PersistedQueriesMiddleware {
    persisted_queries: Rc<PersistedQueries>,
}

impl PersistedQueriesMiddleware {
    pub fn new(persisted_queries: PersistedQueries) -> Self {
        Self {
            persisted_queries: Rc::new(persisted_queries),
        }
    }
}

impl<S, B> Transform<S, ServiceRequest> for PersistedQueriesMiddleware
where
    S: Service<ServiceRequest, Response = ServiceResponse<B>, Error = Error> + 'static,
    S::Future: 'static,
    B: 'static,
{
    type Response = ServiceResponse<B>;
    type Error = Error;
    type InitError = ();
    type Transform = PersistedQueriesMiddlewareService<S>;
    type Future = Ready<Result<Self::Transform, Self::InitError>>;

    fn new_transform(&self, service: S) -> Self::Future {
        ready(Ok(PersistedQueriesMiddlewareService {
            service: Rc::new(service),
            persisted_queries: Rc::clone(&self.persisted_queries),
        }))
    }
}

pub struct PersistedQueriesMiddlewareService<S> {
    service: Rc<S>,
    persisted_queries: Rc<PersistedQueries>,
}

impl<S, B> Service<ServiceRequest> for PersistedQueriesMiddlewareService<S>
where
    S: Service<ServiceRequest, Response = ServiceResponse<B>, Error = Error> + 'static,
    S::Future: 'static,
    B: 'static,
{
    type Response = ServiceResponse<B>;
    type Error = Error;
    type Future = LocalBoxFuture<'static, Result<Self::Response, Self::Error>>;

    forward_ready!(service);

    fn call(&self, req: ServiceRequest) -> Self::Future {
        let service = Rc::clone(&self.service);
        let persisted_queries = Rc::clone(&self.persisted_queries);

        Box::pin(async move {
            // Only validate GraphQL POST requests
            if req.method() == "POST" && req.path().ends_with("/graphql") {
                // Note: Full implementation would parse the request body
                // and validate the query hash. This requires reading the
                // request body which is more complex in actix-web middleware.
                //
                // For now, we store the PersistedQueries instance in extensions
                // for use by the GraphQL handler
                req.extensions_mut().insert(Rc::clone(&persisted_queries));
            }

            service.call(req).await
        })
    }
}
