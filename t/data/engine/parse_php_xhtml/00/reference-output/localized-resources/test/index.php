<?php
    $pageTitle = "Šáḿṕļē Ṕáğē";
    include($_SERVER['DOCUMENT_ROOT'] . '/inc/header.php');
?>

<div id="header">
    <!-- the following line was enclosed in <span lang="en"> and will be explicitly translated -->
    <span><img src="x.png" alt="<? echo $pageTitle; ?>" /></span>

    <!-- another way to mark image as translatable (this will work on terminal tags only like <img />) -->
    <img src="x.png" alt="baz" />

    <!-- the following line was enclosed in <span lang=""> and will be explicitly excluded from translation -->
    <p>&copy; 2012 ACME Corporation</p>

    <!-- in the following image, 'alt' and 'title' attributes will be extracted -->
    <img src="x" alt="ļőçáļĩžáḃļē áļţ áţţŕĩḃũţē ţēҳţ" title="ļőçáļĩžáḃļē ţĩţļē áţţŕĩḃũţē ţēҳţ" />

    <!-- the following image will be extracted as a whole -->
    <img src="x.png" alt="localizable image" />

    <!-- the following image 'alt' and 'title' attributes will NOT be extracted -->
    <img src="x.png" alt="non-localizable alt attribute text" title="non-localizable title attribute text" />

    <!-- the following block will not be localized by default unless the lang="en" option will be provided-->
    <p>
      <ul>
        <li>non-localizable string 1</li>
        <li>ļőçáļĩžáḃļē šţŕĩŋğ 2</li>
      </ul>
    </p>
</div>

<div id="content">
    <!-- <h1>..<h7>, <p> and <li> will be translated by default unless the lang="" attribute is set on them -->

    <h2>Ŧáḃļē őḟ Ćőŋţēŋţš</h2>
    <ul>
        <!-- in the following two lines, the <li> will not be translated as it contains
        the only <a> tag that is explicitly told to be the translation item -->
        <li><a href="#topic1">Ŧőṕĩç 1</a></li>
        <li><a href="#topic2">Ŧőṕĩç 2</a></li>

        <!-- in the subsequent lines, the <li> item will be the default translation item (default behavior) -->
        <li><a href="#topic3">Ŧőṕĩç 3</a></li>
    </ul>

    <h2 id="topic1">Ŧőṕĩç 1</h2>
    <p>Ṕáŕáğŕáṕĥ 1</p>

    <h2 id="topic2">Ŧőṕĩç 2</h2>
    <p>Ṕáŕáğŕáṕĥ 2</p>

    <h2 id="topic2">Ŧőṕĩç 3</h2>
    <!-- One can manually segment large paragraphs (split them into separate translatable sentences) -->
    <p><span>Ṕáŕáğŕáṕĥ 3, Šēŋţēŋçē 1.</span> <span>Ṕáŕáğŕáṕĥ 3, Šēŋţēŋçē 2.</span></p>

    <ul>
        <li>Ĩţēḿ 1</li>
        <li>Ĩţēḿ 2</li>
        <li>Ĩţēḿ 3</li>
    </ul>
</div><!-- /content -->

<?php include($_SERVER['DOCUMENT_ROOT'] . '/inc/footer.php'); ?>