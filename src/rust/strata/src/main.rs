mod agents;
mod cli;
mod config;
mod doctor;
mod index;
mod lifecycle;
mod review;
mod vault;

use cli::{Command, IndexMode};
use std::env;
use std::error::Error;
use std::fs;
use std::path::{Path, PathBuf};

type Result<T> = std::result::Result<T, Box<dyn Error>>;

fn main() {
    match run() {
        Ok(()) => {}
        Err(err) => {
            eprintln!("strata: {err}");
            std::process::exit(1);
        }
    }
}

fn run() -> Result<()> {
    let cli = cli::parse_args(env::args().skip(1).collect())?;

    match cli.command {
        Command::AgentsGenerate => {
            let summary = agents::generate(&cli.vault)?;
            if cli.json {
                println!(
                    "{{\"ok\":true,\"path\":\"{}\",\"profile\":\"{}\"}}",
                    json_escape(&summary.path),
                    json_escape(&summary.profile)
                );
            } else {
                println!("Generated AGENTS.md for profile: {}", summary.profile);
            }
        }
        Command::Index(mode) => {
            let summary = index::refresh(&cli.vault, mode)?;
            if cli.json {
                println!(
                    "{{\"ok\":true,\"backend\":\"{}\",\"indexed\":{}}}",
                    summary.backend, summary.indexed
                );
            } else {
                println!("Indexed {} file(s)", summary.indexed);
            }
        }
        Command::Refresh => {
            let summary = index::refresh(&cli.vault, IndexMode::Full)?;
            if cli.json {
                println!(
                    "{{\"ok\":true,\"backend\":\"{}\",\"indexed\":{}}}",
                    summary.backend, summary.indexed
                );
            } else {
                println!("Refreshed index: {} file(s)", summary.indexed);
            }
        }
        Command::Search(search_args) => {
            index::search(&cli.vault, &search_args, cli.json)?;
        }
        Command::SemanticRefresh => {
            let summary = index::semantic_refresh(&cli.vault)?;
            if cli.json {
                println!(
                    "{{\"ok\":true,\"backend\":\"{}\",\"provider\":\"{}\",\"model\":\"{}\",\"embedding_dim\":{},\"indexed\":{},\"descriptions\":{},\"sections\":{}}}",
                    summary.backend,
                    json_escape(&summary.provider),
                    json_escape(&summary.model),
                    summary.embedding_dim,
                    summary.indexed,
                    summary.descriptions,
                    summary.sections
                );
            } else {
                println!(
                    "Semantic embeddings refreshed: {} item(s) using {}/{}",
                    summary.indexed, summary.provider, summary.model
                );
            }
        }
        Command::SemanticStatus => {
            index::semantic_status(&cli.vault, cli.json)?;
        }
        Command::LinkReview => {
            review::link_review(&cli.vault, cli.json)?;
        }
        Command::PrivacyReview => {
            review::privacy_review(&cli.vault, cli.json)?;
        }
        Command::TagReview => {
            review::tag_review(&cli.vault, cli.json)?;
        }
        Command::RoomReview => {
            review::room_review(&cli.vault, cli.json)?;
        }
        Command::Doctor => {
            doctor::run(&cli.vault, cli.json)?;
        }
        Command::DbMigrate => {
            let summary = index::migrate(&cli.vault)?;
            if cli.json {
                println!(
                    "{{\"ok\":true,\"backend\":\"{}\",\"experimental\":{},\"db\":\"{}\",\"applied\":{}}}",
                    summary.backend,
                    summary.experimental,
                    json_escape(&summary.db_path.to_string_lossy()),
                    summary.applied
                );
            } else {
                println!(
                    "Database migrated: {} ({}, {} applied)",
                    summary.db_path.to_string_lossy(),
                    summary.backend,
                    summary.applied
                );
            }
        }
        Command::Init => {
            vault::init(&cli.vault)?;
            if cli.json {
                println!(
                    "{{\"ok\":true,\"vault\":\"{}\"}}",
                    json_escape(&cli.vault.to_string_lossy())
                );
            } else {
                println!(
                    "Initialized Strata-Memory vault: {}",
                    cli.vault.to_string_lossy()
                );
            }
        }
        Command::ConfigCompile => {
            let summary = config::compile(&cli.vault)?;
            if cli.json {
                println!(
                    "{{\"ok\":true,\"cache\":\"{}\",\"profile\":\"{}\",\"rooms\":{},\"tags\":{}}}",
                    json_escape(&summary.cache.to_string_lossy()),
                    json_escape(&summary.profile),
                    summary.rooms,
                    summary.tags
                );
            } else {
                println!("Compiled config: {}", summary.cache.to_string_lossy());
            }
        }
        Command::Normalize(args) => {
            match lifecycle::normalize(&cli.vault, &args.target, args.check) {
                Ok(summary) => {
                    if cli.json {
                        println!(
                            "{{\"ok\":true,\"path\":\"{}\",\"strata\":\"{}\",\"status\":\"{}\"}}",
                            json_escape(&summary.path),
                            json_escape(&summary.strata),
                            json_escape(&summary.status)
                        );
                    } else if args.check {
                        println!("Normalized check passed: {}", summary.path);
                    } else {
                        println!("Normalized: {}", summary.path);
                    }
                }
                Err(err) if cli.json && err.to_string().contains("description is required") => {
                    let abs = absolute_path(&args.target)?;
                    let rel = rel_path(&abs, &cli.vault)
                        .unwrap_or_else(|| abs.to_string_lossy().to_string());
                    println!(
                        "{{\"ok\":false,\"error\":\"description_required\",\"path\":\"{}\"}}",
                        json_escape(&rel)
                    );
                    return Err(err);
                }
                Err(err) => return Err(err),
            }
        }
        Command::Promote(args) => {
            let summary =
                lifecycle::promote(&cli.vault, &args.source, &args.to, args.new_slug.as_deref())?;
            index::refresh(
                &cli.vault,
                IndexMode::Target(cli.vault.join(&summary.target)),
            )?;
            index::refresh(
                &cli.vault,
                IndexMode::Target(cli.vault.join(&summary.archive)),
            )?;
            if cli.json {
                println!(
                    "{{\"ok\":true,\"target\":\"{}\",\"archive\":\"{}\",\"log\":\"{}\"}}",
                    json_escape(&summary.target),
                    json_escape(&summary.archive),
                    json_escape(&summary.log)
                );
            } else {
                println!("Promoted: {}", summary.target);
                println!("Archived: {}", summary.archive);
            }
        }
        Command::Retention(args) => {
            let summary = lifecycle::retention(&cli.vault, args.apply)?;
            if cli.json {
                println!(
                    "{{\"ok\":true,\"report\":\"{}\",\"mode\":\"{}\",\"candidate_count\":{},\"deleted_count\":{},\"kept_count\":{},\"skipped_count\":{}}}",
                    json_escape(&summary.report),
                    json_escape(&summary.mode),
                    summary.candidate_count,
                    summary.deleted_count,
                    summary.kept_count,
                    summary.skipped_count
                );
            } else {
                println!(
                    "Retention {} complete: {} candidate, {} deleted, {} kept, {} skipped",
                    summary.mode,
                    summary.candidate_count,
                    summary.deleted_count,
                    summary.kept_count,
                    summary.skipped_count
                );
                println!("Report: {}", summary.report);
            }
        }
    }

    Ok(())
}

fn collect_markdown_files_rec(dir: &Path, files: &mut Vec<PathBuf>) -> Result<()> {
    for entry in fs::read_dir(dir)? {
        let entry = entry?;
        let path = entry.path();
        let file_type = entry.file_type()?;
        if file_type.is_dir() {
            collect_markdown_files_rec(&path, files)?;
        } else if file_type.is_file() && path.extension().and_then(|ext| ext.to_str()) == Some("md")
        {
            files.push(path);
        }
    }
    Ok(())
}

fn json_escape(value: &str) -> String {
    let mut out = String::new();
    for ch in value.chars() {
        match ch {
            '\\' => out.push_str("\\\\"),
            '"' => out.push_str("\\\""),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            other => out.push(other),
        }
    }
    out
}

fn absolute_path(path: &Path) -> Result<PathBuf> {
    if path.is_absolute() {
        Ok(path.to_path_buf())
    } else {
        Ok(env::current_dir()?.join(path))
    }
}

fn rel_path(path: &Path, vault: &Path) -> Option<String> {
    let rel = path.strip_prefix(vault).ok()?;
    Some(rel.to_string_lossy().trim_start_matches('/').to_string())
}
