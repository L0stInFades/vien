## Test Result

Total test 652 examples, and failed 108 examples:

|                Section                | Failed/Total  |  Percentage   |
|:-------------------------------------:|:-------------:|:-------------:|
|                 Tabs                  |     0/11      |    100.00%    |
|           Backslash escapes           |     1/13      |    92.31%     |
|Entity and numeric character references|     3/17      |    82.35%     |
|              Precedence               |      0/1      |    100.00%    |
|            Thematic breaks            |     0/19      |    100.00%    |
|             ATX headings              |     0/18      |    100.00%    |
|            Setext headings            |     3/27      |    88.89%     |
|         Indented code blocks          |     0/12      |    100.00%    |
|          Fenced code blocks           |     0/29      |    100.00%    |
|              HTML blocks              |     1/44      |    97.73%     |
|      Link reference definitions       |     3/27      |    88.89%     |
|              Paragraphs               |      0/8      |    100.00%    |
|              Blank lines              |      0/1      |    100.00%    |
|             Block quotes              |     2/25      |    92.00%     |
|              List items               |     12/48     |    75.00%     |
|                 Lists                 |     10/26     |    61.54%     |
|                Inlines                |      0/1      |    100.00%    |
|              Code spans               |     0/22      |    100.00%    |
|     Emphasis and strong emphasis      |    37/132     |    71.97%     |
|                 Links                 |     17/90     |    81.11%     |
|                Images                 |     14/22     |    36.36%     |
|               Autolinks               |     4/19      |    78.95%     |
|               Raw HTML                |     1/20      |    95.00%     |
|           Hard line breaks            |     0/15      |    100.00%    |
|           Soft line breaks            |      0/2      |    100.00%    |
|            Textual content            |      0/3      |    100.00%    |

**Example23**

```markdown
Markdown content
[foo]

[foo]: /bar\* "ti\*tle"

Expected Html
<p><a href="/bar*" title="ti*tle">foo</a></p>

Actural Html
<p><a href="/bar%5C*" title="ti\*tle">foo</a></p>

```

**Example28**

```markdown
Markdown content
&nbsp &x; &#; &#x;
&#87654321;
&#abcdef0;
&ThisIsNotDefined; &hi?;

Expected Html
<p>&amp;nbsp &amp;x; &amp;#; &amp;#x;
&amp;#87654321;
&amp;#abcdef0;
&amp;ThisIsNotDefined; &amp;hi?;</p>

Actural Html
<p>&amp;nbsp &x; &amp;#; &#x;
&#87654321;
&#abcdef0;
&ThisIsNotDefined; &amp;hi?;</p>

```

**Example32**

```markdown
Markdown content
[foo](/f&ouml;&ouml; "f&ouml;&ouml;")

Expected Html
<p><a href="/f%C3%B6%C3%B6" title="föö">foo</a></p>

Actural Html
<p><a href="/f&ouml;&ouml;" title="f&ouml;&ouml;">foo</a></p>

```

**Example33**

```markdown
Markdown content
[foo]

[foo]: /f&ouml;&ouml; "f&ouml;&ouml;"

Expected Html
<p><a href="/f%C3%B6%C3%B6" title="föö">foo</a></p>

Actural Html
<p><a href="/f&ouml;&ouml;" title="f&ouml;&ouml;">foo</a></p>

```

**Example81**

```markdown
Markdown content
Foo *bar
baz*
====

Expected Html
<h1>Foo <em>bar
baz</em></h1>

Actural Html
<p>Foo <em>bar
baz</em>
====</p>

```

**Example82**

```markdown
Markdown content
  Foo *bar
baz*
====

Expected Html
<h1>Foo <em>bar
baz</em></h1>

Actural Html
<p>  Foo <em>bar
baz</em><br>====</p>

```

**Example95**

```markdown
Markdown content
Foo
Bar
---

Expected Html
<h2>Foo
Bar</h2>

Actural Html
<p>Foo
Bar</p>
<hr>

```

**Example171**

```markdown
Markdown content
<textarea>

*foo*

_bar_

</textarea>

Expected Html
<textarea>

*foo*

_bar_

</textarea>

Actural Html
<textarea>

<p><em>foo</em></p>
<p><em>bar</em></p>
</textarea>

```

**Example195**

```markdown
Markdown content
[Foo bar]:
<my url>
'title'

[Foo bar]

Expected Html
<p><a href="my%20url" title="title">Foo bar</a></p>

Actural Html
<p>[Foo bar]:
<my url>
&#39;title&#39;</p>
<p>[Foo bar]</p>

```

**Example200**

```markdown
Markdown content
[foo]: <>

[foo]

Expected Html
<p><a href="">foo</a></p>

Actural Html
<p><a href="%3C">foo</a></p>

```

**Example202**

```markdown
Markdown content
[foo]: /url\bar\*baz "foo\"bar\baz"

[foo]

Expected Html
<p><a href="/url%5Cbar*baz" title="foo&quot;bar\baz">foo</a></p>

Actural Html
<p><a href="/url%5Cbar%5C*baz" title="foo\&quot;bar\baz">foo</a></p>

```

**Example236**

```markdown
Markdown content
>     foo
    bar

Expected Html
<blockquote>
<pre><code>foo
</code></pre>
</blockquote>
<pre><code>bar
</code></pre>

Actural Html
<blockquote>
<pre><code class="indented-code-block">foo
bar</code></pre>
</blockquote>

```

**Example237**

```markdown
Markdown content
> \`\`\`
foo
\`\`\`

Expected Html
<blockquote>
<pre><code></code></pre>
</blockquote>
<p>foo</p>
<pre><code></code></pre>

Actural Html
<blockquote>
<pre><code class="fenced-code-block">foo</code></pre>
</blockquote>
<pre><code class="fenced-code-block"></code></pre>

```

**Example255**

```markdown
Markdown content
- one

 two

Expected Html
<ul>
<li>one</li>
</ul>
<p>two</p>

Actural Html
<ul>
<li><p>one</p>
<p>two</p>
</li>
</ul>

```

**Example257**

```markdown
Markdown content
 -    one

     two

Expected Html
<ul>
<li>one</li>
</ul>
<pre><code> two
</code></pre>

Actural Html
<ul>
<li><p>one</p>
<p>two</p>
</li>
</ul>

```

**Example262**

```markdown
Markdown content
- foo


  bar

Expected Html
<ul>
<li>
<p>foo</p>
<p>bar</p>
</li>
</ul>

Actural Html
<ul>
<li>foo</li>
</ul>
<p>  bar</p>

```

**Example264**

```markdown
Markdown content
- Foo

      bar


      baz

Expected Html
<ul>
<li>
<p>Foo</p>
<pre><code>bar


baz
</code></pre>
</li>
</ul>

Actural Html
<ul>
<li><p>Foo</p>
<pre><code class="indented-code-block">bar</code></pre>
</li>
</ul>
<pre><code class="indented-code-block">  baz</code></pre>

```

**Example273**

```markdown
Markdown content
1.     indented code

   paragraph

       more code

Expected Html
<ol>
<li>
<pre><code>indented code
</code></pre>
<p>paragraph</p>
<pre><code>more code
</code></pre>
</li>
</ol>

Actural Html
<ol>
<li><p>indented code</p>
<p>paragraph</p>
<p> more code</p>
</li>
</ol>

```

**Example274**

```markdown
Markdown content
1.      indented code

   paragraph

       more code

Expected Html
<ol>
<li>
<pre><code> indented code
</code></pre>
<p>paragraph</p>
<pre><code>more code
</code></pre>
</li>
</ol>

Actural Html
<ol>
<li><p>indented code</p>
<p>paragraph</p>
<p> more code</p>
</li>
</ol>

```

**Example276**

```markdown
Markdown content
-    foo

  bar

Expected Html
<ul>
<li>foo</li>
</ul>
<p>bar</p>

Actural Html
<ul>
<li><p>foo</p>
<p>bar</p>
</li>
</ul>

```

**Example278**

```markdown
Markdown content
-
  foo
-
  \`\`\`
  bar
  \`\`\`
-
      baz

Expected Html
<ul>
<li>foo</li>
<li>
<pre><code>bar
</code></pre>
</li>
<li>
<pre><code>baz
</code></pre>
</li>
</ul>

Actural Html
<p>-
  foo
-</p>
<pre><code class="fenced-code-block">bar</code></pre>
<p>-
      baz</p>

```

**Example280**

```markdown
Markdown content
-

  foo

Expected Html
<ul>
<li></li>
</ul>
<p>foo</p>

Actural Html
<p>-</p>
<p>  foo</p>

```

**Example284**

```markdown
Markdown content
*

Expected Html
<ul>
<li></li>
</ul>

Actural Html
<p>*</p>

```

**Example295**

```markdown
Markdown content
- foo
 - bar
  - baz
   - boo

Expected Html
<ul>
<li>foo</li>
<li>bar</li>
<li>baz</li>
<li>boo</li>
</ul>

Actural Html
<ul>
<li>foo<ul>
<li>bar</li>
<li>baz<ul>
<li>boo</li>
</ul>
</li>
</ul>
</li>
</ul>

```

**Example297**

```markdown
Markdown content
10) foo
   - bar

Expected Html
<ol start="10">
<li>foo</li>
</ol>
<ul>
<li>bar</li>
</ul>

Actural Html
<ol start="10">
<li>foo<ul>
<li>bar</li>
</ul>
</li>
</ol>

```

**Example306**

```markdown
Markdown content
- foo

- bar


- baz

Expected Html
<ul>
<li>
<p>foo</p>
</li>
<li>
<p>bar</p>
</li>
<li>
<p>baz</p>
</li>
</ul>

Actural Html
<ul>
<li><p>foo</p>
</li>
<li><p>bar</p>
</li>
</ul>
<ul>
<li>baz</li>
</ul>

```

**Example307**

```markdown
Markdown content
- foo
  - bar
    - baz


      bim

Expected Html
<ul>
<li>foo
<ul>
<li>bar
<ul>
<li>
<p>baz</p>
<p>bim</p>
</li>
</ul>
</li>
</ul>
</li>
</ul>

Actural Html
<ul>
<li>foo<ul>
<li>bar<ul>
<li>baz</li>
</ul>
</li>
</ul>
</li>
</ul>
<pre><code class="indented-code-block">  bim</code></pre>

```

**Example310**

```markdown
Markdown content
- a
 - b
  - c
   - d
  - e
 - f
- g

Expected Html
<ul>
<li>a</li>
<li>b</li>
<li>c</li>
<li>d</li>
<li>e</li>
<li>f</li>
<li>g</li>
</ul>

Actural Html
<ul>
<li>a<ul>
<li>b</li>
<li>c<ul>
<li>d</li>
</ul>
</li>
<li>e</li>
<li>f</li>
</ul>
</li>
<li>g</li>
</ul>

```

**Example311**

```markdown
Markdown content
1. a

  2. b

   3. c

Expected Html
<ol>
<li>
<p>a</p>
</li>
<li>
<p>b</p>
</li>
<li>
<p>c</p>
</li>
</ol>

Actural Html
<ol>
<li><p>a</p>
<ol start="2">
<li><p>b</p>
</li>
<li><p>c</p>
</li>
</ol>
</li>
</ol>

```

**Example312**

```markdown
Markdown content
- a
 - b
  - c
   - d
    - e

Expected Html
<ul>
<li>a</li>
<li>b</li>
<li>c</li>
<li>d
- e</li>
</ul>

Actural Html
<ul>
<li>a<ul>
<li>b</li>
<li>c<ul>
<li>d</li>
<li>e</li>
</ul>
</li>
</ul>
</li>
</ul>

```

**Example313**

```markdown
Markdown content
1. a

  2. b

    3. c

Expected Html
<ol>
<li>
<p>a</p>
</li>
<li>
<p>b</p>
</li>
</ol>
<pre><code>3. c
</code></pre>

Actural Html
<ol>
<li><p>a</p>
<ol start="2">
<li><p>b</p>
<ol start="3">
<li>c</li>
</ol>
</li>
</ol>
</li>
</ol>

```

**Example315**

```markdown
Markdown content
* a
*

* c

Expected Html
<ul>
<li>
<p>a</p>
</li>
<li></li>
<li>
<p>c</p>
</li>
</ul>

Actural Html
<ul>
<li><p>a</p>
</li>
<li><p></p>
</li>
<li><p>c</p>
</li>
</ul>

```

**Example317**

```markdown
Markdown content
- a
- b

  [ref]: /url
- d

Expected Html
<ul>
<li>
<p>a</p>
</li>
<li>
<p>b</p>
</li>
<li>
<p>d</p>
</li>
</ul>

Actural Html
<ul>
<li>a</li>
<li>b</li>
</ul>
<ul>
<li>d</li>
</ul>

```

**Example318**

```markdown
Markdown content
- a
- \`\`\`
  b


  \`\`\`
- c

Expected Html
<ul>
<li>a</li>
<li>
<pre><code>b


</code></pre>
</li>
<li>c</li>
</ul>

Actural Html
<ul>
<li>a</li>
<li><pre><code class="fenced-code-block">b

</code></pre>
</li>
</ul>
<pre><code class="fenced-code-block">- c</code></pre>

```

**Example319**

```markdown
Markdown content
- a
  - b

    c
- d

Expected Html
<ul>
<li>a
<ul>
<li>
<p>b</p>
<p>c</p>
</li>
</ul>
</li>
<li>d</li>
</ul>

Actural Html
<ul>
<li><p>a</p>
<ul>
<li><p>b</p>
<p>c</p>
</li>
</ul>
</li>
<li><p>d</p>
</li>
</ul>

```

**Example354**

```markdown
Markdown content
*$*alpha.

*£*bravo.

*€*charlie.

Expected Html
<p>*$*alpha.</p>
<p>*£*bravo.</p>
<p>*€*charlie.</p>

Actural Html
<p>*$*alpha.</p>
<p><em>£</em>bravo.</p>
<p><em>€</em>charlie.</p>

```

**Example369**

```markdown
Markdown content
*(*foo*)*

Expected Html
<p><em>(<em>foo</em>)</em></p>

Actural Html
<p>*(<em>foo</em>)*</p>

```

**Example373**

```markdown
Markdown content
_(_foo_)_

Expected Html
<p><em>(<em>foo</em>)</em></p>

Actural Html
<p>_(<em>foo</em>)_</p>

```

**Example389**

```markdown
Markdown content
__foo, __bar__, baz__

Expected Html
<p><strong>foo, <strong>bar</strong>, baz</strong></p>

Actural Html
<p><strong>foo, __bar</strong>, baz__</p>

```

**Example391**

```markdown
Markdown content
**foo bar **

Expected Html
<p>**foo bar **</p>

Actural Html
<p>*<em>foo bar *</em></p>

```

**Example402**

```markdown
Markdown content
__foo__bar__baz__

Expected Html
<p><strong>foo__bar__baz</strong></p>

Actural Html
<p>__foo__bar__baz__</p>

```

**Example407**

```markdown
Markdown content
_foo _bar_ baz_

Expected Html
<p><em>foo <em>bar</em> baz</em></p>

Actural Html
<p><em>foo _bar</em> baz_</p>

```

**Example408**

```markdown
Markdown content
__foo_ bar_

Expected Html
<p><em><em>foo</em> bar</em></p>

Actural Html
<p><em>_foo</em> bar_</p>

```

**Example413**

```markdown
Markdown content
***foo** bar*

Expected Html
<p><em><strong>foo</strong> bar</em></p>

Actural Html
<p><strong>*foo</strong> bar*</p>

```

**Example414**

```markdown
Markdown content
*foo **bar***

Expected Html
<p><em>foo <strong>bar</strong></em></p>

Actural Html
<p>*foo <strong>bar*</strong></p>

```

**Example415**

```markdown
Markdown content
*foo**bar***

Expected Html
<p><em>foo<strong>bar</strong></em></p>

Actural Html
<p>*foo<strong>bar*</strong></p>

```

**Example416**

```markdown
Markdown content
foo***bar***baz

Expected Html
<p>foo<em><strong>bar</strong></em>baz</p>

Actural Html
<p>foo***bar***baz</p>

```

**Example417**

```markdown
Markdown content
foo******bar*********baz

Expected Html
<p>foo<strong><strong><strong>bar</strong></strong></strong>***baz</p>

Actural Html
<p>foo******bar*********baz</p>

```

**Example418**

```markdown
Markdown content
*foo **bar *baz* bim** bop*

Expected Html
<p><em>foo <strong>bar <em>baz</em> bim</strong> bop</em></p>

Actural Html
<p><em>foo **bar *baz</em> bim** bop*</p>

```

**Example419**

```markdown
Markdown content
*foo [*bar*](/url)*

Expected Html
<p><em>foo <a href="/url"><em>bar</em></a></em></p>

Actural Html
<p>*foo <a href="/url"><em>bar</em></a>*</p>

```

**Example425**

```markdown
Markdown content
__foo __bar__ baz__

Expected Html
<p><strong>foo <strong>bar</strong> baz</strong></p>

Actural Html
<p><strong>foo __bar</strong> baz__</p>

```

**Example426**

```markdown
Markdown content
____foo__ bar__

Expected Html
<p><strong><strong>foo</strong> bar</strong></p>

Actural Html
<p><strong>__foo</strong> bar__</p>

```

**Example432**

```markdown
Markdown content
**foo *bar **baz**
bim* bop**

Expected Html
<p><strong>foo <em>bar <strong>baz</strong>
bim</em> bop</strong></p>

Actural Html
<p><strong>foo *bar **baz</strong>
bim* bop**</p>

```

**Example442**

```markdown
Markdown content
**foo*

Expected Html
<p>*<em>foo</em></p>

Actural Html
<p><em>*foo</em></p>

```

**Example443**

```markdown
Markdown content
*foo**

Expected Html
<p><em>foo</em>*</p>

Actural Html
<p><em>foo*</em></p>

```

**Example444**

```markdown
Markdown content
***foo**

Expected Html
<p>*<strong>foo</strong></p>

Actural Html
<p><strong>*foo</strong></p>

```

**Example445**

```markdown
Markdown content
****foo*

Expected Html
<p>***<em>foo</em></p>

Actural Html
<p><em>***foo</em></p>

```

**Example446**

```markdown
Markdown content
**foo***

Expected Html
<p><strong>foo</strong>*</p>

Actural Html
<p><strong>foo*</strong></p>

```

**Example447**

```markdown
Markdown content
*foo****

Expected Html
<p><em>foo</em>***</p>

Actural Html
<p><em>foo***</em></p>

```

**Example454**

```markdown
Markdown content
__foo_

Expected Html
<p>_<em>foo</em></p>

Actural Html
<p><em>_foo</em></p>

```

**Example455**

```markdown
Markdown content
_foo__

Expected Html
<p><em>foo</em>_</p>

Actural Html
<p><em>foo_</em></p>

```

**Example456**

```markdown
Markdown content
___foo__

Expected Html
<p>_<strong>foo</strong></p>

Actural Html
<p><strong>_foo</strong></p>

```

**Example457**

```markdown
Markdown content
____foo_

Expected Html
<p>___<em>foo</em></p>

Actural Html
<p><em>___foo</em></p>

```

**Example458**

```markdown
Markdown content
__foo___

Expected Html
<p><strong>foo</strong>_</p>

Actural Html
<p><strong>foo_</strong></p>

```

**Example459**

```markdown
Markdown content
_foo____

Expected Html
<p><em>foo</em>___</p>

Actural Html
<p><em>foo___</em></p>

```

**Example466**

```markdown
Markdown content
******foo******

Expected Html
<p><strong><strong><strong>foo</strong></strong></strong></p>

Actural Html
<p>*<strong><strong><em>foo*</em></strong></strong></p>

```

**Example467**

```markdown
Markdown content
***foo***

Expected Html
<p><em><strong>foo</strong></em></p>

Actural Html
<p><strong><em>foo</em></strong></p>

```

**Example468**

```markdown
Markdown content
_____foo_____

Expected Html
<p><em><strong><strong>foo</strong></strong></em></p>

Actural Html
<p><strong><strong><em>foo</em></strong></strong></p>

```

**Example471**

```markdown
Markdown content
**foo **bar baz**

Expected Html
<p>**foo <strong>bar baz</strong></p>

Actural Html
<p><strong>foo **bar baz</strong></p>

```

**Example472**

```markdown
Markdown content
*foo *bar baz*

Expected Html
<p>*foo <em>bar baz</em></p>

Actural Html
<p><em>foo *bar baz</em></p>

```

**Example478**

```markdown
Markdown content
*a \`*\`*

Expected Html
<p><em>a <code>*</code></em></p>

Actural Html
<p>*a <code>*</code>*</p>

```

**Example479**

```markdown
Markdown content
_a \`_\`_

Expected Html
<p><em>a <code>_</code></em></p>

Actural Html
<p>_a <code>_</code>_</p>

```

**Example493**

```markdown
Markdown content
[link](<foo\>)

Expected Html
<p>[link](&lt;foo&gt;)</p>

Actural Html
<p>undefined</p>

```

**Example494**

```markdown
Markdown content
[a](<b)c
[a](<b)c>
[a](<b>c)

Expected Html
<p>[a](&lt;b)c
[a](&lt;b)c&gt;
[a](<b>c)</p>

Actural Html
<p>undefined</p>

```

**Example497**

```markdown
Markdown content
[link](foo(and(bar))

Expected Html
<p>[link](foo(and(bar))</p>

Actural Html
<p><a href="foo(and(bar)">link</a></p>

```

**Example503**

```markdown
Markdown content
[link](foo%20b&auml;)

Expected Html
<p><a href="foo%20b%C3%A4">link</a></p>

Actural Html
<p><a href="foo%20b&auml;">link</a></p>

```

**Example507**

```markdown
Markdown content
[link](/url "title")

Expected Html
<p><a href="/url%C2%A0%22title%22">link</a></p>

Actural Html
<p><a href="/url" title="title">link</a></p>

```

**Example512**

```markdown
Markdown content
[link [foo [bar]]](/uri)

Expected Html
<p><a href="/uri">link [foo [bar]]</a></p>

Actural Html
<p>[link [foo [bar]]](/uri)</p>

```

**Example518**

```markdown
Markdown content
[foo [bar](/uri)](/uri)

Expected Html
<p>[foo <a href="/uri">bar</a>](/uri)</p>

Actural Html
<p><a href="/uri">foo <a href="/uri">bar</a></a></p>

```

**Example519**

```markdown
Markdown content
[foo *[bar [baz](/uri)](/uri)*](/uri)

Expected Html
<p>[foo <em>[bar <a href="/uri">baz</a>](/uri)</em>](/uri)</p>

Actural Html
<p>[foo *<a href="/uri">bar <a href="/uri">baz</a></a>*](/uri)</p>

```

**Example520**

```markdown
Markdown content
![[[foo](uri1)](uri2)](uri3)

Expected Html
<p><img src="uri3" alt="[foo](uri2)" /></p>

Actural Html
<p>![<a href="uri2"><a href="uri1">foo</a></a>](uri3)</p>

```

**Example528**

```markdown
Markdown content
[link [foo [bar]]][ref]

[ref]: /uri

Expected Html
<p><a href="/uri">link [foo [bar]]</a></p>

Actural Html
<p>[link [foo [bar]]]<a href="/uri">ref</a></p>

```

**Example532**

```markdown
Markdown content
[foo [bar](/uri)][ref]

[ref]: /uri

Expected Html
<p>[foo <a href="/uri">bar</a>]<a href="/uri">ref</a></p>

Actural Html
<p><a href="/uri">foo <a href="/uri">bar</a></a></p>

```

**Example533**

```markdown
Markdown content
[foo *bar [baz][ref]*][ref]

[ref]: /uri

Expected Html
<p>[foo <em>bar <a href="/uri">baz</a></em>]<a href="/uri">ref</a></p>

Actural Html
<p><a href="/uri">foo <em>bar <a href="/uri">baz</a></em></a></p>

```

**Example534**

```markdown
Markdown content
*[foo*][ref]

[ref]: /uri

Expected Html
<p>*<a href="/uri">foo*</a></p>

Actural Html
<p><em>[foo</em>]<a href="/uri">ref</a></p>

```

**Example536**

```markdown
Markdown content
[foo <bar attr="][ref]">

[ref]: /uri

Expected Html
<p>[foo <bar attr="][ref]"></p>

Actural Html
<p><a href="/uri">foo &lt;bar attr=&quot;</a>&quot;&gt;</p>

```

**Example538**

```markdown
Markdown content
[foo<https://example.com/?search=][ref]>

[ref]: /uri

Expected Html
<p>[foo<a href="https://example.com/?search=%5D%5Bref%5D">https://example.com/?search=][ref]</a></p>

Actural Html
<p><a href="/uri">foo&lt;https://example.com/?search=</a>&gt;</p>

```

**Example540**

```markdown
Markdown content
[ẞ]

[SS]: /url

Expected Html
<p><a href="/url">ẞ</a></p>

Actural Html
<p>[ẞ]</p>

```

**Example564**

```markdown
Markdown content
[foo*]: /url

*[foo*]

Expected Html
<p>*<a href="/url">foo*</a></p>

Actural Html
<p><em>[foo</em>]</p>

```

**Example572**

```markdown
Markdown content
![foo](/url "title")

Expected Html
<p><img src="/url" alt="foo" title="title" /></p>

Actural Html
<p><img src="file:///url" alt="foo" title="title"></p>

```

**Example574**

```markdown
Markdown content
![foo ![bar](/url)](/url2)

Expected Html
<p><img src="/url2" alt="foo bar" /></p>

Actural Html
<p><img src="file:///url2" alt="foo ![bar](/url)"></p>

```

**Example575**

```markdown
Markdown content
![foo [bar](/url)](/url2)

Expected Html
<p><img src="/url2" alt="foo bar" /></p>

Actural Html
<p><img src="file:///url2" alt="foo [bar](/url)"></p>

```

**Example579**

```markdown
Markdown content
My ![foo bar](/path/to/train.jpg  "title"   )

Expected Html
<p>My <img src="/path/to/train.jpg" alt="foo bar" title="title" /></p>

Actural Html
<p>My <img src="file:///path/to/train.jpg" alt="foo bar" title="title"></p>

```

**Example581**

```markdown
Markdown content
![](/url)

Expected Html
<p><img src="/url" alt="" /></p>

Actural Html
<p><img src="file:///url" alt=""></p>

```

**Example582**

```markdown
Markdown content
![foo][bar]

[bar]: /url

Expected Html
<p><img src="/url" alt="foo" /></p>

Actural Html
<p><img src="file:///url" alt="foo"></p>

```

**Example583**

```markdown
Markdown content
![foo][bar]

[BAR]: /url

Expected Html
<p><img src="/url" alt="foo" /></p>

Actural Html
<p><img src="file:///url" alt="foo"></p>

```

**Example584**

```markdown
Markdown content
![foo][]

[foo]: /url "title"

Expected Html
<p><img src="/url" alt="foo" title="title" /></p>

Actural Html
<p><img src="file:///url" alt="foo" title="title"></p>

```

**Example585**

```markdown
Markdown content
![*foo* bar][]

[*foo* bar]: /url "title"

Expected Html
<p><img src="/url" alt="foo bar" title="title" /></p>

Actural Html
<p><img src="file:///url" alt="foo bar" title="title"></p>

```

**Example586**

```markdown
Markdown content
![Foo][]

[foo]: /url "title"

Expected Html
<p><img src="/url" alt="Foo" title="title" /></p>

Actural Html
<p><img src="file:///url" alt="Foo" title="title"></p>

```

**Example587**

```markdown
Markdown content
![foo]
[]

[foo]: /url "title"

Expected Html
<p><img src="/url" alt="foo" title="title" />
[]</p>

Actural Html
<p><img src="file:///url" alt="foo" title="title">
[]</p>

```

**Example588**

```markdown
Markdown content
![foo]

[foo]: /url "title"

Expected Html
<p><img src="/url" alt="foo" title="title" /></p>

Actural Html
<p><img src="file:///url" alt="foo" title="title"></p>

```

**Example589**

```markdown
Markdown content
![*foo* bar]

[*foo* bar]: /url "title"

Expected Html
<p><img src="/url" alt="foo bar" title="title" /></p>

Actural Html
<p><img src="file:///url" alt="foo bar" title="title"></p>

```

**Example591**

```markdown
Markdown content
![Foo]

[foo]: /url "title"

Expected Html
<p><img src="/url" alt="Foo" title="title" /></p>

Actural Html
<p><img src="file:///url" alt="Foo" title="title"></p>

```

**Example602**

```markdown
Markdown content
<https://foo.bar/baz bim>

Expected Html
<p>&lt;https://foo.bar/baz bim&gt;</p>

Actural Html
<p>&lt;<a href="https://foo.bar/baz">https://foo.bar/baz</a> bim&gt;</p>

```

**Example608**

```markdown
Markdown content
< https://foo.bar >

Expected Html
<p>&lt; https://foo.bar &gt;</p>

Actural Html
<p>&lt; <a href="https://foo.bar">https://foo.bar</a> &gt;</p>

```

**Example611**

```markdown
Markdown content
https://example.com

Expected Html
<p>https://example.com</p>

Actural Html
<p><a href="https://example.com">https://example.com</a></p>

```

**Example612**

```markdown
Markdown content
foo@bar.example.com

Expected Html
<p>foo@bar.example.com</p>

Actural Html
<p><a href="mailto:foo@bar.example.com">foo@bar.example.com</a></p>

```

**Example626**

```markdown
Markdown content
foo <!--> foo -->

foo <!---> foo -->

Expected Html
<p>foo <!--> foo --&gt;</p>
<p>foo <!---> foo --&gt;</p>

Actural Html
<p>foo &lt;!--&gt; foo --&gt;</p>
<p>foo &lt;!---&gt; foo --&gt;</p>

```

