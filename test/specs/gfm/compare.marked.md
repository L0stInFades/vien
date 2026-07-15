## Compare with `marked.js`

Marked.js failed examples count: 4
MarkText failed examples count: 0

**Example633**

MarkText success and marked.js fail

```markdown
Markdown content
mailto:foo@bar.baz

mailto:a.b-c_d@a.b

mailto:a.b-c_d@a.b.

mailto:a.b-c_d@a.b/

mailto:a.b-c_d@a.b-

mailto:a.b-c_d@a.b_

xmpp:foo@bar.baz

xmpp:foo@bar.baz.
Expected Html
<p><a href="mailto:foo@bar.baz">mailto:foo@bar.baz</a></p>
<p><a href="mailto:a.b-c_d@a.b">mailto:a.b-c_d@a.b</a></p>
<p><a href="mailto:a.b-c_d@a.b">mailto:a.b-c_d@a.b</a>.</p>
<p><a href="mailto:a.b-c_d@a.b">mailto:a.b-c_d@a.b</a>/</p>
<p>mailto:a.b-c_d@a.b-</p>
<p>mailto:a.b-c_d@a.b_</p>
<p><a href="xmpp:foo@bar.baz">xmpp:foo@bar.baz</a></p>
<p><a href="xmpp:foo@bar.baz">xmpp:foo@bar.baz</a>.</p>
Actural Html
<p>mailto:foo@bar.baz</p>
<p>mailto:a.b-c_d@a.b</p>
<p>mailto:a.b-c_d@a.b.</p>
<p>mailto:a.b-c_d@a.b/</p>
<p>mailto:a.b-c_d@a.b-</p>
<p>mailto:a.b-c_d@a.b_</p>
<p>xmpp:foo@bar.baz</p>
<p>xmpp:foo@bar.baz.</p>

marked.js html
<p>mailto:<a href="mailto:&#102;&#111;&#111;&#x40;&#x62;&#97;&#114;&#46;&#x62;&#x61;&#x7a;">&#102;&#111;&#111;&#x40;&#x62;&#97;&#114;&#46;&#x62;&#x61;&#x7a;</a></p>
<p>mailto:<a href="mailto:&#x61;&#x2e;&#x62;&#45;&#99;&#x5f;&#x64;&#64;&#x61;&#46;&#x62;">&#x61;&#x2e;&#x62;&#45;&#99;&#x5f;&#x64;&#64;&#x61;&#46;&#x62;</a></p>
<p>mailto:<a href="mailto:&#97;&#46;&#x62;&#45;&#99;&#95;&#100;&#x40;&#x61;&#x2e;&#x62;">&#97;&#46;&#x62;&#45;&#99;&#95;&#100;&#x40;&#x61;&#x2e;&#x62;</a>.</p>
<p>mailto:<a href="mailto:&#x61;&#x2e;&#x62;&#x2d;&#x63;&#x5f;&#100;&#x40;&#97;&#46;&#98;">&#x61;&#x2e;&#x62;&#x2d;&#x63;&#x5f;&#100;&#x40;&#97;&#46;&#98;</a>/</p>
<p>mailto:a.b-c_d@a.b-</p>
<p>mailto:a.b-c_d@a.b_</p>
<p>xmpp:<a href="mailto:&#x66;&#111;&#x6f;&#64;&#98;&#x61;&#114;&#x2e;&#x62;&#97;&#x7a;">&#x66;&#111;&#x6f;&#64;&#98;&#x61;&#114;&#x2e;&#x62;&#97;&#x7a;</a></p>
<p>xmpp:<a href="mailto:&#102;&#x6f;&#111;&#64;&#98;&#x61;&#x72;&#46;&#98;&#97;&#x7a;">&#102;&#x6f;&#111;&#64;&#98;&#x61;&#x72;&#46;&#98;&#97;&#x7a;</a>.</p>

```

**Example634**

MarkText success and marked.js fail

```markdown
Markdown content
xmpp:foo@bar.baz/txt

xmpp:foo@bar.baz/txt@bin

xmpp:foo@bar.baz/txt@bin.com
Expected Html
<p><a href="xmpp:foo@bar.baz/txt">xmpp:foo@bar.baz/txt</a></p>
<p><a href="xmpp:foo@bar.baz/txt@bin">xmpp:foo@bar.baz/txt@bin</a></p>
<p><a href="xmpp:foo@bar.baz/txt@bin.com">xmpp:foo@bar.baz/txt@bin.com</a></p>
Actural Html
<p>xmpp:foo@bar.baz/txt</p>
<p>xmpp:foo@bar.baz/txt@bin</p>
<p>xmpp:foo@bar.baz/txt@bin.com</p>

marked.js html
<p>xmpp:<a href="mailto:&#102;&#111;&#x6f;&#64;&#98;&#x61;&#114;&#46;&#98;&#97;&#x7a;">&#102;&#111;&#x6f;&#64;&#98;&#x61;&#114;&#46;&#98;&#97;&#x7a;</a>/txt</p>
<p>xmpp:<a href="mailto:&#x66;&#x6f;&#x6f;&#x40;&#x62;&#x61;&#x72;&#x2e;&#x62;&#97;&#x7a;">&#x66;&#x6f;&#x6f;&#x40;&#x62;&#x61;&#x72;&#x2e;&#x62;&#97;&#x7a;</a>/txt@bin</p>
<p>xmpp:<a href="mailto:&#x66;&#x6f;&#111;&#x40;&#x62;&#x61;&#114;&#46;&#98;&#x61;&#x7a;">&#x66;&#x6f;&#111;&#x40;&#x62;&#x61;&#114;&#46;&#98;&#x61;&#x7a;</a>/txt@bin.com</p>

```

**Example635**

MarkText success and marked.js fail

```markdown
Markdown content
xmpp:foo@bar.baz/txt/bin
Expected Html
<p><a href="xmpp:foo@bar.baz/txt">xmpp:foo@bar.baz/txt</a>/bin</p>
Actural Html
<p>xmpp:foo@bar.baz/txt/bin</p>

marked.js html
<p>xmpp:<a href="mailto:&#x66;&#x6f;&#x6f;&#64;&#x62;&#x61;&#x72;&#46;&#98;&#x61;&#122;">&#x66;&#x6f;&#x6f;&#64;&#x62;&#x61;&#x72;&#46;&#98;&#x61;&#122;</a>/txt/bin</p>

```

**Example657**

MarkText success and marked.js fail

```markdown
Markdown content
<strong> <title> <style> <em>

<blockquote>
  <xmp> is disallowed.  <XMP> is also disallowed.
</blockquote>
Expected Html
<p><strong> &lt;title> &lt;style> <em></p>
<blockquote>
  &lt;xmp> is disallowed.  &lt;XMP> is also disallowed.
</blockquote>
Actural Html
<p><strong> <title> <style> <em></p>
<blockquote>
  <xmp> is disallowed.  <XMP> is also disallowed.
</blockquote>
marked.js html
<p><strong> <title> <style> <em></p>
<blockquote>
  <xmp> is disallowed.  <XMP> is also disallowed.
</blockquote>
```

There are 4 examples are different with marked.js.