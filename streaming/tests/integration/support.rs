use std::net::{SocketAddr, TcpListener};

use actix_web::{dev::ServerHandle, web, App, HttpServer};
use streaming_delivery::status_publisher::StreamStatusPublisher;
use streaming_delivery::websocket_handler::websocket_handler;
use streaming_delivery::websocket_hub::WebSocketHub;

pub async fn start_websocket_server(
    hub: WebSocketHub,
    publisher: StreamStatusPublisher,
) -> std::io::Result<(SocketAddr, ServerHandle)> {
    let hub_data = hub.clone();
    let publisher_data = publisher.clone();

    let listener = TcpListener::bind("127.0.0.1:0")?;
    let addr = listener.local_addr()?;

    let server = HttpServer::new(move || {
        App::new()
            .app_data(web::Data::new(hub_data.clone()))
            .app_data(web::Data::new(publisher_data.clone()))
            .service(websocket_handler)
    })
    .workers(1)
    .listen(listener)?
    .run();

    let handle = server.handle();
    actix_rt::spawn(server);
    Ok((addr, handle))
}
