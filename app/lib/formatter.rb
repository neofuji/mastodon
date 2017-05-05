# frozen_string_literal: true

require 'singleton'
require_relative './sanitize_config'

class Formatter
  include Singleton
  include RoutingHelper

  include ActionView::Helpers::TextHelper

  def format(status)
    return reformat(status.content) unless status.local?

    html = split_codes(status.text).each_slice(4).map do |_, text, lang, code|
      html = text
      unless html.empty?
        html = encode_and_link_urls(html)
        html = simple_format(html, {}, sanitize: false)
        html = html.delete("\n")
        html = link_mentions(html, status.mentions)
        html = link_hashtags(html)
      end
      if lang
        html += "<span style=\"display: none;\"><br />```<br /></span><pre class=\"prettyprint\"><code>#{encode(code).gsub("\n", "<br />")}</code></pre><span style=\"display: none;\"><br />```<br /></span>"
      end
      html
    end.join(nil)

    html.html_safe # rubocop:disable Rails/OutputSafety
  end

  def reformat(html)
    sanitize(html, Sanitize::Config::MASTODON_STRICT).html_safe # rubocop:disable Rails/OutputSafety
  end

  def plaintext(status)
    return status.text if status.local?
    strip_tags(status.text)
  end

  def simplified_format(account)
    return reformat(account.note) unless account.local?

    html = encode_and_link_urls(account.note)
    html = simple_format(html, {}, sanitize: false)
    html = html.delete("\n")
    html = link_accounts(html)
    html = link_hashtags(html)

    html.html_safe # rubocop:disable Rails/OutputSafety
  end

  def sanitize(html, config)
    Sanitize.fragment(html, config)
  end

  def split_codes(text)
    array = text.split(/^```()(?:\n|\Z)/, -1)
    return array if array.empty?
    array.unshift(nil)
    1.upto((array.size - 2) / 4) do |i|
      array[i * 4 + 1] = "#{array[i * 4]}\n#{array[i * 4 + 1]}" unless array[i * 4].empty?
      array[i * 4] = nil
    end
    if array[-1].empty?
      array[-3] = "#{array[-3]}```#{array[-2]}" if array.size % 4 == 0
      array.pop(2)
    end
    array.each_with_index {|str, i| str.chop! if i.odd? && str.end_with?("\n") }
  end

  def remove_codes(text)
    split_codes(text).select.with_index {|_, i| i % 4 == 1 }.join("\n").strip
  end

  private

  def encode(html)
    HTMLEntities.new.encode(html)
  end

  def encode_and_link_urls(html)
    entities = Twitter::Extractor.extract_urls_with_indices(html, extract_url_without_protocol: false)
    entities = entities.sort_by { |entity| entity[:indices].first }

    chars = html.to_s.to_char_a
    html_attrs = {
      target: '_blank',
      rel: 'nofollow noopener',
    }
    result = ''

    last_index = entities.reduce(0) do |index, entity|
      normalized_url = Addressable::URI.parse(entity[:url]).normalize
      indices = entity[:indices]
      result += encode(chars[index...indices.first].join)
      result += Twitter::Autolink.send(:link_to_text, entity, link_html(entity[:url]), normalized_url, html_attrs)
      indices.last
    end
    result += encode(chars[last_index..-1].join)
  end

  def link_mentions(html, mentions)
    html.gsub(Account::MENTION_RE) do |match|
      acct    = Account::MENTION_RE.match(match)[1]
      mention = mentions.find { |item| TagManager.instance.same_acct?(item.account.acct, acct) }

      mention.nil? ? match : mention_html(match, mention.account)
    end
  end

  def link_accounts(html)
    html.gsub(Account::MENTION_RE) do |match|
      acct = Account::MENTION_RE.match(match)[1]
      username, domain = acct.split('@')
      domain = nil if TagManager.instance.local_domain?(domain)
      account = Account.find_remote(username, domain)

      account.nil? ? match : mention_html(match, account)
    end
  end

  def link_hashtags(html)
    html.gsub(Tag::HASHTAG_RE) do |match|
      hashtag_html(match)
    end
  end

  def link_html(url)
    url = Addressable::URI.parse(url).display_uri.to_s
    prefix = url.match(/\Ahttps?:\/\/(www\.)?/).to_s
    text   = url[prefix.length, 30]
    suffix = url[prefix.length + 30..-1]
    cutoff = url[prefix.length..-1].length > 30

    "<span class=\"invisible\">#{prefix}</span><span class=\"#{cutoff ? 'ellipsis' : ''}\">#{text}</span><span class=\"invisible\">#{suffix}</span>"
  end

  def hashtag_html(match)
    prefix, _, affix = match.rpartition('#')
    "#{prefix}<a href=\"#{tag_url(affix.downcase)}\" class=\"mention hashtag\">#<span>#{affix}</span></a>"
  end

  def mention_html(match, account)
    "#{match.split('@').first}<span class=\"h-card\"><a href=\"#{TagManager.instance.url_for(account)}\" class=\"u-url mention\">@<span>#{account.username}</span></a></span>"
  end
end
