import urllib.request
import urllib.error
import re
import json
import os
import sys
from html.parser import HTMLParser

# Ensure standard output can handle Unicode emojis on Windows console
if hasattr(sys.stdout, 'reconfigure'):
    try:
        sys.stdout.reconfigure(encoding='utf-8')
    except Exception:
        pass


# Target configurations
BASE_URL = "https://ingress.com"
NEWS_URL = "https://ingress.com/news"
USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

class NewsIndexParser(HTMLParser):
    """Parses the main Ingress news list page to extract article URLs, titles, and timestamps."""
    def __init__(self):
        super().__init__()
        self.articles = []
        self.current_article = None
        self.in_card = False
        self.in_title = False
        self.card_depth = 0

    def handle_starttag(self, tag, attrs):
        attrs_dict = dict(attrs)
        # Ingress cards have href="/news/..."
        if tag == 'a' and 'href' in attrs_dict and attrs_dict['href'].startswith('/news/'):
            href = attrs_dict['href']
            # Avoid duplicate listings or self-links to /news
            if href != '/news' and href != '/news/':
                self.current_article = {
                    "url": BASE_URL + href,
                    "id": href.replace('/news/', ''),
                    "title": "",
                    "published_at": 0
                }
                self.in_card = True
                self.card_depth = 1

        elif self.in_card:
            self.card_depth += 1
            if tag == 'eve-date-format' and 'timestamp' in attrs_dict:
                try:
                    self.current_article["published_at"] = int(attrs_dict['timestamp'])
                except ValueError:
                    pass
            elif tag in ['h3', 'h4'] or 'class' in attrs_dict and 'title' in attrs_dict['class'].lower():
                self.in_title = True

    def handle_endtag(self, tag):
        if self.in_card:
            self.card_depth -= 1
            if self.card_depth == 0:
                self.in_card = False
                # If we have a valid article structure, save it
                if self.current_article and self.current_article["id"]:
                    # Clean title whitespace
                    self.current_article["title"] = self.current_article["title"].strip()
                    # De-duplicate: check if url already added
                    if not any(a['url'] == self.current_article['url'] for a in self.articles):
                        self.articles.append(self.current_article)
                self.current_article = None
            
            if tag in ['h3', 'h4']:
                self.in_title = False

    def handle_data(self, data):
        if self.in_card and self.in_title and self.current_article:
            self.current_article["title"] += data

class ArticleContentParser(HTMLParser):
    """Parses a single Ingress article page to extract the core text content under <main>."""
    def __init__(self):
        super().__init__()
        self.in_main = False
        self.main_depth = 0
        self.text_blocks = []
        self.current_tag = ""

    def handle_starttag(self, tag, attrs):
        attrs_dict = dict(attrs)
        if tag == 'main' or attrs_dict.get('id') == 'main':
            self.in_main = True
            self.main_depth = 0
        
        if self.in_main:
            self.main_depth += 1
            if tag in ['p', 'h1', 'h2', 'h3', 'h4', 'li']:
                self.current_tag = tag

    def handle_endtag(self, tag):
        if self.in_main:
            self.main_depth -= 1
            if self.main_depth <= 0:
                self.in_main = False
            self.current_tag = ""

    def handle_data(self, data):
        if self.in_main and data.strip():
            text = data.strip()
            # Clean typographic replacements (like smart quotes)
            text = text.replace('\u2018', "'").replace('\u2019', "'").replace('\u201c', '"').replace('\u201d', '"')
            self.text_blocks.append(text)

def fetch_url(url):
    req = urllib.request.Request(url, headers={'User-Agent': USER_AGENT})
    with urllib.request.urlopen(req) as response:
        return response.read().decode('utf-8')

def main():
    print("Fetching Ingress news feed...")
    try:
        index_html = fetch_url(NEWS_URL)
    except Exception as e:
        print(f"Error fetching news index: {e}")
        return

    # Parse articles list
    parser = NewsIndexParser()
    parser.feed(index_html)
    scraped_articles = parser.articles
    print(f"Found {len(scraped_articles)} articles on page.")

    # Load existing database if available
    db_path = "events.json"
    existing_ids = set()
    if os.path.exists(db_path):
        try:
            with open(db_path, "r", encoding="utf-8") as f:
                existing_data = json.load(f)
                for entry in existing_data:
                    existing_ids.add(entry["id"])
        except Exception as e:
            print(f"Warning reading events.json: {e}")

    # Determine which articles are new
    new_articles = [a for a in scraped_articles if a["id"] not in existing_ids]
    print(f"New articles to process: {len(new_articles)}")
    
    if not new_articles:
        print("No new articles discovered.")
        # Ensure any leftover file is deleted
        if os.path.exists("new_articles.json"):
            os.remove("new_articles.json")
        return

    articles_to_process = []
    for art in new_articles:
        print(f"Scraping new article content: {art['title']} ({art['url']})...")
        try:
            art_html = fetch_url(art["url"])
            art_parser = ArticleContentParser()
            art_parser.feed(art_html)
            
            # Combine extracted paragraph/header texts
            full_text = "\n\n".join(art_parser.text_blocks)
            art["content_text"] = full_text
            articles_to_process.append(art)
        except Exception as e:
            print(f"Failed to fetch content for {art['url']}: {e}")

    # Save to intermediate JSON file for Antigravity-assisted parsing
    if articles_to_process:
        output_path = "new_articles.json"
        with open(output_path, "w", encoding="utf-8") as f:
            json.dump(articles_to_process, f, indent=2, ensure_ascii=False)
        print(f"Saved {len(articles_to_process)} new articles to {output_path} for processing.")

if __name__ == "__main__":
    main()
