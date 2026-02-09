use crate::core::scraper::{ScrapedMetadata, ScrapedResource, ScraperSearchResult, ScraperProvider, client::ScraperClient};
use async_trait::async_trait;
use scraper::{Html, Selector};
use std::sync::Arc;
use anyhow::Result;

pub struct WikipediaProvider {
    client: Arc<ScraperClient>,
}

impl WikipediaProvider {
    pub fn new(client: Arc<ScraperClient>) -> Self {
        Self { client }
    }
}

#[async_trait]
impl ScraperProvider for WikipediaProvider {
    fn name(&self) -> &'static str {
        "Wikipedia"
    }

    async fn search(&self, query: &str, _platform: Option<&str>) -> Result<Vec<ScraperSearchResult>> {
        // Use Wikipedia search
        let url = format!("https://en.wikipedia.org/w/index.php?search={}", urlencoding::encode(query));
        let html_content = self.client.get(&url).await?;
        let document = Html::parse_document(&html_content);
        
        let mut results = Vec::new();

        // Check if we were redirected directly to an article
        let title_selector = Selector::parse("h1#firstHeading").unwrap();
        if let Some(h1) = document.select(&title_selector).next() {
            let title = h1.text().collect::<String>().trim().to_string();
            // If it's not a search results page, it's a direct article
            if title != "Search results" {
                results.push(ScraperSearchResult {
                    id: title.replace(" ", "_"),
                    title,
                    platform: "Wikipedia".to_string(),
                    platforms: None,
                    platform_ids: None,
                    region: None,
                    release_year: None,
                    thumbnail_url: None,
                    resolution: None,
                    can_add_to_collection: false,
                    metadata: None,
                });
                return Ok(results);
            }
        }

        // Parse search results page
        let result_selector = Selector::parse(".mw-search-result-heading a").unwrap();
        for element in document.select(&result_selector) {
            let title = element.text().collect::<String>().trim().to_string();
            let href = element.value().attr("href").unwrap_or("");
            
            if !title.is_empty() && href.starts_with("/wiki/") {
                let id = href.trim_start_matches("/wiki/").to_string();
                results.push(ScraperSearchResult {
                    id,
                    title,
                    platform: "Wikipedia".to_string(),
                    platforms: None,
                    platform_ids: None,
                    region: None,
                    release_year: None,
                    thumbnail_url: None,
                    resolution: None,
                    can_add_to_collection: false,
                    metadata: None,
                });
            }
        }

        Ok(results)
    }

    async fn fetch_details(&self, result_id: &str) -> Result<ScrapedMetadata> {
        let url = format!("https://en.wikipedia.org/wiki/{}", result_id);
        // println!("[Wikipedia] Fetching details for: {}", url);
        let html_content = self.client.get(&url).await?;
        let document = Html::parse_document(&html_content);
        
        let mut metadata = ScrapedMetadata::default();
        metadata.source = "Wikipedia".to_string();
        metadata.source_id = result_id.to_string();

        // Title
        let title_selector = Selector::parse("h1#firstHeading").unwrap();
        if let Some(h1) = document.select(&title_selector).next() {
            metadata.title = h1.text().collect::<String>().trim().to_string();
        }

        // Description - First two paragraphs of the main content that aren't empty or a coordinate/metadata
        let p_selector = Selector::parse(".mw-parser-output > p").unwrap();
        let mut paragraphs = Vec::new();
        for p in document.select(&p_selector) {
            let text = p.text().collect::<String>().trim().to_string();
            // Skip empty paragraphs or those that are likely not the lead (e.g. coordinates, "This article is about...")
            if text.len() > 50 && !text.starts_with("Coordinates:") {
                // Clean up citations [1], [2], [a], [b], etc.
                let cleaned_text = regex::Regex::new(r"\[[\da-z]+\]").unwrap().replace_all(&text, "").to_string();
                paragraphs.push(cleaned_text);
                
                if paragraphs.len() >= 2 {
                    break;
                }
            }
        }
        metadata.description = paragraphs.join("\n\n");

        // Infobox Metadata
        let infobox_selector = Selector::parse("table.infobox").unwrap();
        if let Some(infobox) = document.select(&infobox_selector).next() {
            let row_selector = Selector::parse("tr").unwrap();
            let th_selector = Selector::parse("th").unwrap();
            let td_selector = Selector::parse("td").unwrap();

            for row in infobox.select(&row_selector) {
                if let (Some(th), Some(td)) = (row.select(&th_selector).next(), row.select(&td_selector).next()) {
                    let key = th.text().collect::<String>().trim().to_lowercase();
                    
                    // Improved text extraction that skips <style> and <script> tags
                    // and joins with spaces to prevent mashing
                    let value = extract_clean_text(&td);
                    
                    // Clean up citations [1], [2], [a], [b], etc.
                    let value = regex::Regex::new(r"\[[\da-z]+\]").unwrap().replace_all(&value, "").to_string();

                    if key.contains("developer") {
                        metadata.developer = value;
                    } else if key.contains("publisher") {
                        metadata.publisher = value;
                    } else if key.contains("genre") {
                        metadata.genre = value;
                    } else if key.contains("release") {
                        // Try to extract year - look for 4 consecutive digits
                        if let Some(caps) = regex::Regex::new(r"(\d{4})").unwrap().captures(&value) {
                            if let Ok(year) = caps[1].parse::<i32>() {
                                // Wikipedia often lists multiple release dates, we'll take the first one found
                                if metadata.release_year.is_none() {
                                    metadata.release_year = Some(year);
                                }
                            }
                        }
                    }
                }
            }

            // Main Image
            let img_selector = Selector::parse("td.infobox-image img, .infobox img").unwrap();
            if let Some(img) = infobox.select(&img_selector).next() {
                if let Some(src) = img.value().attr("src") {
                    let full_src = if src.starts_with("//") {
                        format!("https:{}", src)
                    } else if src.starts_with("/") {
                        format!("https://en.wikipedia.org{}", src)
                    } else {
                        src.to_string()
                    };
                    
                    metadata.assets.entry("Box - Front".to_string())
                        .or_insert_with(Vec::new)
                        .push(full_src);
                }
            }
        }
        
        let mut resources = Vec::new();
        
        // Infobox Website links - Best source for "Official"
        if let Some(infobox) = document.select(&Selector::parse("table.infobox").unwrap()).next() {
             let url_selector = Selector::parse("a.external").unwrap();
             for link in infobox.select(&url_selector) {
                 let href = link.value().attr("href").unwrap_or("");
                 if !href.is_empty() && (href.starts_with("http") || href.starts_with("//")) {
                     let clean_url = if href.starts_with("//") { format!("https:{}", href) } else { href.to_string() };
                     resources.push(ScrapedResource {
                         type_: "Official".to_string(),
                         url: clean_url,
                         label: "Official Website".to_string(),
                     });
                 }
             }
        }
        
        // External Links Logic
        // Strategy: Find the "External links" H2, then look at immediate siblings for the UL
        let h2_selector = Selector::parse("h2").unwrap();
        
        // Find the specific H2 header
        let mut found_header_node = None;
        
        for h2 in document.select(&h2_selector) {
            let text = h2.text().collect::<String>().to_lowercase();
            // Check span id as well
            let span_selector = Selector::parse("span.mw-headline").unwrap();
            let span_id = h2.select(&span_selector).next()
                .and_then(|s| s.value().id())
                .unwrap_or("").to_lowercase();
                
            if text.contains("external links") || span_id.contains("external_links") {
                // println!("[Wikipedia] Found External Links Header: {}", text);
                found_header_node = Some(h2);
                break;
            }
        }

        if let Some(header) = found_header_node {
            // Traverse siblings until we find a UL or hit another H2
            let mut current_node = header.next_sibling();
            
            while let Some(node) = current_node {
                if let Some(element) = node.value().as_element() {
                    let name = element.name();
                    if name == "ul" {
                        // println!("[Wikipedia] Found UL after header");
                        let ul_ref = scraper::ElementRef::wrap(node).unwrap();
                        let a_selector = Selector::parse("li a").unwrap();
                        
                        for link in ul_ref.select(&a_selector) {
                            let href = link.value().attr("href").unwrap_or("");
                            let label = link.text().collect::<String>();
                            
                            if !href.is_empty() && (href.starts_with("http") || href.starts_with("//")) {
                                 if href.contains("wikipedia.org") || href.contains("wikidata.org") || href.contains("archive.org") {
                                     continue;
                                 }
                                 
                                 let clean_url = if href.starts_with("//") { format!("https:{}", href) } else { href.to_string() };
                                 // println!("[Wikipedia] Found Link: {} -> {}", label, clean_url);
                                 
                                 let type_ = if label.to_lowercase().contains("moby") { "MobyGames" }
                                             else if label.to_lowercase().contains("steam") { "Steam" }
                                             else if label.to_lowercase().contains("gog.com") { "GOG" }
                                             else if label.to_lowercase().contains("official") { "Official" }
                                             else { "Web" };
                                             
                                 resources.push(ScrapedResource {
                                     type_: type_.to_string(),
                                     url: clean_url,
                                     label: label,
                                 });
                            }
                        }
                    } else if name == "div" {
                         // Sometimes lists are wrapped in divs (columns, navbox)
                         // Try to find UL inside
                         let div_ref = scraper::ElementRef::wrap(node).unwrap();
                         let ul_selector = Selector::parse("ul").unwrap();
                         for ul in div_ref.select(&ul_selector) {
                             // Same extraction logic
                             let a_selector = Selector::parse("li a").unwrap();
                             for link in ul.select(&a_selector) {
                                let href = link.value().attr("href").unwrap_or("");
                                let label = link.text().collect::<String>();
                                if !href.is_empty() && (href.starts_with("http") || href.starts_with("//")) {
                                     if href.contains("wikipedia.org") || href.contains("wikidata.org") || href.contains("archive.org") { continue; }
                                     let clean_url = if href.starts_with("//") { format!("https:{}", href) } else { href.to_string() };
                                     // println!("[Wikipedia] Found Link (in div): {} -> {}", label, clean_url);
                                     let type_ = if label.to_lowercase().contains("moby") { "MobyGames" }
                                                 else if label.to_lowercase().contains("steam") { "Steam" }
                                                 else if label.to_lowercase().contains("gog.com") { "GOG" }
                                                 else if label.to_lowercase().contains("official") { "Official" }
                                                 else { "Web" };
                                     resources.push(ScrapedResource { type_: type_.to_string(), url: clean_url, label: label });
                                }
                             }
                         }
                    } else if name == "h2" || name == "h3" {
                        // Hit next section
                        break;
                    }
                }
                current_node = node.next_sibling();
            }
        } else {
             // println!("[Wikipedia] External links header NOT found");
        }
        
        // FALLBACK: Scan the entire document for high-value links if we haven't found much
        // This is "loose" but essential if the strict structure check fails.
        if resources.is_empty() {
             // println!("[Wikipedia] Strict structure check failed. Scanning all external links...");
             let all_ext_selector = Selector::parse("a.external").unwrap();
             for link in document.select(&all_ext_selector) {
                 let href = link.value().attr("href").unwrap_or("");
                 let text = link.text().collect::<String>().trim().to_string();
                 
                 if !href.is_empty() && (href.starts_with("http") || href.starts_with("//")) {
                     let clean_url = if href.starts_with("//") { format!("https:{}", href) } else { href.to_string() };
                     let lower_text = text.to_lowercase();
                     let lower_url = clean_url.to_lowercase();
                     
                     let mut type_: Option<&str> = None;
                     
                     if lower_text.contains("official website") || lower_text.contains("official site") { type_ = Some("Official"); }
                     else if lower_url.contains("mobygames.com") { type_ = Some("MobyGames"); }
                     else if lower_url.contains("steampowered.com") { type_ = Some("Steam"); }
                     else if lower_url.contains("gog.com") { type_ = Some("GOG"); }
                     else if lower_url.contains("gamefaqs") { type_ = Some("GameFAQs"); }
                     
                     if let Some(t) = type_ {
                         // Check for duplicates
                         if !resources.iter().any(|r| r.url == clean_url) {
                             // println!("[Wikipedia] Found Fallback Link: {} -> {}", text, clean_url);
                             resources.push(ScrapedResource {
                                 type_: t.to_string(),
                                 url: clean_url,
                                 label: text,
                             });
                         }
                     }
                 }
             }
        }

        // Always add the Wikipedia page itself
        resources.push(ScrapedResource {
            type_: "Wikipedia".to_string(),
            url: url.clone(),
            label: "Wikipedia".to_string(),
        });
        
        metadata.resources = resources;
        Ok(metadata)
    }
}

/// Recursively extract text from an element, skipping style and script tags,
/// and joining text nodes with spaces to prevent mashing.
fn extract_clean_text(element: &scraper::ElementRef) -> String {
    let mut text = String::new();
    
    for node in element.children() {
        if let Some(t) = node.value().as_text() {
            let trimmed = t.trim();
            if !trimmed.is_empty() {
                if !text.is_empty() && !text.ends_with(' ') {
                    text.push(' ');
                }
                text.push_str(trimmed);
            }
        } else if let Some(e) = node.value().as_element() {
            // Skip style and script tags
            if e.name() == "style" || e.name() == "script" {
                continue;
            }
            
            // Recursively extract from children
            if let Some(child_ref) = scraper::ElementRef::wrap(node) {
                let child_text = extract_clean_text(&child_ref);
                if !child_text.is_empty() {
                    if !text.is_empty() && !text.ends_with(' ') {
                        text.push(' ');
                    }
                    text.push_str(&child_text);
                }
            }
        }
    }
    
    text.to_string()
}

#[cfg(test)]
mod tests {
    use super::*;
    use scraper::{Html, Selector};

    #[test]
    fn test_extract_clean_text_with_style() {
        let html = r#"
            <html><body><table><tr>
                <td>
                    <style>.some-css { color: red; }</style>
                    <div class="plainlist">
                        <ul>
                            <li>WW: Focus Entertainment</li>
                            <li>CIS: VK Play</li>
                            <li>AS: 4Divinity</li>
                        </ul>
                    </div>
                </td>
            </tr></table></body></html>
        "#;
        let document = Html::parse_document(html);
        let selector = Selector::parse("td").unwrap();
        let td = document.select(&selector).next().expect("Should find td element");
        
        let cleaned = extract_clean_text(&td);
        // Should NOT contain the CSS content
        assert!(!cleaned.contains(".some-css"));
        // Should contain the publishers with some separation
        assert!(cleaned.contains("Focus Entertainment"));
        assert!(cleaned.contains("VK Play"));
        assert!(cleaned.contains("4Divinity"));
        
       
        assert!(cleaned.contains("Entertainment CIS"));
    }
}
