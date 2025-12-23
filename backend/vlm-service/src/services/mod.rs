//! VLM service business logic

pub mod channel_matcher;
pub mod tag_generator;

pub use channel_matcher::{match_channels, Channel, ChannelMatch, KeywordWeight};
pub use tag_generator::{generate_tags, GeneratedTag, TagSource};
