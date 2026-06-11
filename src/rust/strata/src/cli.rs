use crate::Result;
use std::env;
use std::path::PathBuf;

#[derive(Debug)]
pub(crate) struct Cli {
    pub(crate) command: Command,
    pub(crate) vault: PathBuf,
    pub(crate) json: bool,
}

#[derive(Debug)]
pub(crate) enum Command {
    AgentsGenerate,
    Index(IndexMode),
    Search(SearchArgs),
    LinkReview,
    DbMigrate,
    Init,
    ConfigCompile,
    Normalize(NormalizeArgs),
    Promote(PromoteArgs),
    Retention(RetentionArgs),
}

#[derive(Debug)]
pub(crate) enum IndexMode {
    Full,
    Target(PathBuf),
}

#[derive(Debug)]
pub(crate) struct SearchArgs {
    pub(crate) query: String,
    pub(crate) limit: usize,
    pub(crate) include_archived: bool,
    pub(crate) paths_only: bool,
}

#[derive(Debug)]
pub(crate) struct NormalizeArgs {
    pub(crate) target: PathBuf,
    pub(crate) check: bool,
}

#[derive(Debug)]
pub(crate) struct RetentionArgs {
    pub(crate) apply: bool,
}

#[derive(Debug)]
pub(crate) struct PromoteArgs {
    pub(crate) source: PathBuf,
    pub(crate) to: String,
    pub(crate) new_slug: Option<String>,
}

pub(crate) fn parse_args(args: Vec<String>) -> Result<Cli> {
    if args.is_empty() || args.iter().any(|arg| arg == "--help" || arg == "-h") {
        print_usage();
        std::process::exit(0);
    }

    let mut iter = args.into_iter();
    let mut vault = env::var("STRATA_VAULT")
        .map(PathBuf::from)
        .unwrap_or_else(|_| home_dir().join(".strata-memory"));
    let mut json = false;
    let command = iter.next().ok_or("missing command")?;

    let parsed_command = match command.as_str() {
        "agents-generate" => {
            while let Some(arg) = iter.next() {
                match arg.as_str() {
                    "--vault" => {
                        let value = iter.next().ok_or("--vault requires PATH")?;
                        vault = PathBuf::from(value);
                    }
                    "--json" => json = true,
                    other => return Err(format!("unknown argument: {other}").into()),
                }
            }
            Command::AgentsGenerate
        }
        "index" => {
            let mut full = false;
            let mut target: Option<PathBuf> = None;

            while let Some(arg) = iter.next() {
                match arg.as_str() {
                    "--full" => full = true,
                    "--target" => {
                        let value = iter.next().ok_or("--target requires FILE")?;
                        target = Some(PathBuf::from(value));
                    }
                    "--vault" => {
                        let value = iter.next().ok_or("--vault requires PATH")?;
                        vault = PathBuf::from(value);
                    }
                    "--json" => json = true,
                    other => return Err(format!("unknown argument: {other}").into()),
                }
            }

            let mode = match (full, target) {
                (true, Some(_)) => return Err("use either --target or --full, not both".into()),
                (true, None) => IndexMode::Full,
                (false, Some(path)) => IndexMode::Target(path),
                (false, None) => IndexMode::Full,
            };
            Command::Index(mode)
        }
        "search" => {
            let mut query: Option<String> = None;
            let mut limit = 10;
            let mut include_archived = false;
            let mut paths_only = false;

            while let Some(arg) = iter.next() {
                match arg.as_str() {
                    "--query" | "-q" => {
                        query = Some(iter.next().ok_or("--query requires TEXT")?);
                    }
                    "--vault" => {
                        let value = iter.next().ok_or("--vault requires PATH")?;
                        vault = PathBuf::from(value);
                    }
                    "--limit" => {
                        let value = iter.next().ok_or("--limit requires N")?;
                        limit = value
                            .parse::<usize>()
                            .map_err(|_| "limit must be a positive integer")?;
                    }
                    "--include-archived" => include_archived = true,
                    "--paths-only" => paths_only = true,
                    "--json" => json = true,
                    other if query.is_none() => query = Some(other.to_string()),
                    other => return Err(format!("unknown argument: {other}").into()),
                }
            }

            if limit == 0 {
                return Err("limit must be a positive integer".into());
            }

            Command::Search(SearchArgs {
                query: query.ok_or("missing search query")?,
                limit,
                include_archived,
                paths_only,
            })
        }
        "link-review" => {
            while let Some(arg) = iter.next() {
                match arg.as_str() {
                    "--vault" => {
                        let value = iter.next().ok_or("--vault requires PATH")?;
                        vault = PathBuf::from(value);
                    }
                    "--json" => json = true,
                    other => return Err(format!("unknown argument: {other}").into()),
                }
            }
            Command::LinkReview
        }
        "db-migrate" => {
            while let Some(arg) = iter.next() {
                match arg.as_str() {
                    "--vault" => {
                        let value = iter.next().ok_or("--vault requires PATH")?;
                        vault = PathBuf::from(value);
                    }
                    "--json" => json = true,
                    other => return Err(format!("unknown argument: {other}").into()),
                }
            }
            Command::DbMigrate
        }
        "init" => {
            while let Some(arg) = iter.next() {
                match arg.as_str() {
                    "--vault" => {
                        let value = iter.next().ok_or("--vault requires PATH")?;
                        vault = PathBuf::from(value);
                    }
                    "--json" => json = true,
                    other => return Err(format!("unknown argument: {other}").into()),
                }
            }
            Command::Init
        }
        "config-compile" => {
            while let Some(arg) = iter.next() {
                match arg.as_str() {
                    "--vault" => {
                        let value = iter.next().ok_or("--vault requires PATH")?;
                        vault = PathBuf::from(value);
                    }
                    "--json" => json = true,
                    other => return Err(format!("unknown argument: {other}").into()),
                }
            }
            Command::ConfigCompile
        }
        "normalize" => {
            let mut target: Option<PathBuf> = None;
            let mut check = false;
            while let Some(arg) = iter.next() {
                match arg.as_str() {
                    "--target" => {
                        let value = iter.next().ok_or("--target requires FILE")?;
                        target = Some(PathBuf::from(value));
                    }
                    "--vault" => {
                        let value = iter.next().ok_or("--vault requires PATH")?;
                        vault = PathBuf::from(value);
                    }
                    "--check" => check = true,
                    "--json" => json = true,
                    other => return Err(format!("unknown argument: {other}").into()),
                }
            }
            Command::Normalize(NormalizeArgs {
                target: target.ok_or("missing --target")?,
                check,
            })
        }
        "retention" => {
            let mut apply = false;
            while let Some(arg) = iter.next() {
                match arg.as_str() {
                    "--vault" => {
                        let value = iter.next().ok_or("--vault requires PATH")?;
                        vault = PathBuf::from(value);
                    }
                    "--apply" => apply = true,
                    "--json" => json = true,
                    other => return Err(format!("unknown argument: {other}").into()),
                }
            }
            Command::Retention(RetentionArgs { apply })
        }
        "promote" => {
            let mut source: Option<PathBuf> = None;
            let mut to: Option<String> = None;
            let mut new_slug: Option<String> = None;
            while let Some(arg) = iter.next() {
                match arg.as_str() {
                    "--source" => {
                        let value = iter.next().ok_or("--source requires FILE")?;
                        source = Some(PathBuf::from(value));
                    }
                    "--to" => {
                        to = Some(iter.next().ok_or("--to requires TIER")?);
                    }
                    "--new-slug" => {
                        new_slug = Some(iter.next().ok_or("--new-slug requires SLUG")?);
                    }
                    "--vault" => {
                        let value = iter.next().ok_or("--vault requires PATH")?;
                        vault = PathBuf::from(value);
                    }
                    "--json" => json = true,
                    other => return Err(format!("unknown argument: {other}").into()),
                }
            }
            Command::Promote(PromoteArgs {
                source: source.ok_or("missing --source")?,
                to: to.ok_or("missing --to")?,
                new_slug,
            })
        }
        _ => return Err(format!("unknown command: {command}").into()),
    };

    Ok(Cli {
        command: parsed_command,
        vault,
        json,
    })
}

fn print_usage() {
    println!("Usage: strata index [--target FILE | --full] [--vault PATH] [--json]");
    println!("       strata agents-generate [--vault PATH] [--json]");
    println!("       strata search --query TEXT [--vault PATH] [--limit N] [--include-archived] [--paths-only] [--json]");
    println!("       strata link-review [--vault PATH] [--json]");
    println!("       strata db-migrate [--vault PATH] [--json]");
    println!("       strata init [--vault PATH] [--json]");
    println!("       strata config-compile [--vault PATH] [--json]");
    println!("       strata normalize --target FILE [--vault PATH] [--check] [--json]");
    println!("       strata promote --source FILE --to 2_knowledge|3_intelligence [--new-slug SLUG] [--vault PATH] [--json]");
    println!("       strata retention [--vault PATH] [--apply] [--json]");
}

fn home_dir() -> PathBuf {
    env::var("HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|_| PathBuf::from("."))
}
