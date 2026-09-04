## Test Result

Total test 28 examples, and failed 4 examples:

|      Section      | Failed/Total  |  Percentage   |
|:-----------------:|:-------------:|:-------------:|
|      Tables       |      0/8      |    100.00%    |
|  Task list items  |      0/2      |    100.00%    |
|   Strikethrough   |      0/3      |    100.00%    |
|     Autolinks     |     3/14      |    78.57%     |
|Disallowed Raw HTML|      1/1      |     0.00%     |

**Example633**

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

```

**Example634**

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

```

**Example635**

```markdown
Markdown content
xmpp:foo@bar.baz/txt/bin
Expected Html
<p><a href="xmpp:foo@bar.baz/txt">xmpp:foo@bar.baz/txt</a>/bin</p>
Actural Html
<p>xmpp:foo@bar.baz/txt/bin</p>

```

**Example657**

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
```

