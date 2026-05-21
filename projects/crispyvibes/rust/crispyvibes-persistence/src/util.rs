use anyhow::{bail, Result};

pub fn now_iso() -> String {
    // Simple UTC timestamp without external crate
    let dur = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default();
    let secs = dur.as_secs();
    // Format as ISO 8601 using libc gmtime
    let mut tm: libc::tm = unsafe { std::mem::zeroed() };
    let time_t = secs as libc::time_t;
    unsafe { libc::gmtime_r(&time_t, &mut tm) };
    format!(
        "{:04}-{:02}-{:02}T{:02}:{:02}:{:02}Z",
        tm.tm_year + 1900, tm.tm_mon + 1, tm.tm_mday,
        tm.tm_hour, tm.tm_min, tm.tm_sec
    )
}

pub fn validate_json_object(s: &str) -> Result<()> {
    if s.len() > 65536 {
        bail!("metadata exceeds 64 KB limit");
    }
    let v: serde_json::Value = serde_json::from_str(s).map_err(|_| anyhow::anyhow!("invalid JSON"))?;
    if !v.is_object() {
        bail!("metadata must be a JSON object");
    }
    Ok(())
}

pub fn validate_json_array(s: &str) -> Result<()> {
    let v: serde_json::Value = serde_json::from_str(s).map_err(|_| anyhow::anyhow!("invalid JSON"))?;
    let arr = v.as_array().ok_or_else(|| anyhow::anyhow!("tags must be a JSON array"))?;
    if arr.len() > 100 {
        bail!("tags array exceeds 100 entries");
    }
    for item in arr {
        let s = item.as_str().ok_or_else(|| anyhow::anyhow!("each tag must be a string"))?;
        if s.len() > 256 {
            bail!("tag exceeds 256 character limit");
        }
    }
    Ok(())
}
