<?php
    $pageTitle = "Sample Page";
    include($_SERVER['DOCUMENT_ROOT'] . '/inc/header.php');
?>

<div id="header">
    <!-- the following line was enclosed in <span lang="en"> and will be explicitly translated -->
    <span lang="en"><img src="x.png" alt="<? echo $pageTitle; ?>" /></span>

    <!-- another way to mark image as translatable (this will work on terminal tags only like <img />) -->
    <img lang="en" src="x.png" alt="baz" />

    <!-- the following line was enclosed in <span lang=""> and will be explicitly excluded from translation -->
    <p lang="">&copy; 2012 ACME Corporation</p>

    <!-- in the following image, 'alt' and 'title' attributes will be extracted -->
    <img src="x" alt="localizable alt attribute text" title="localizable title attribute text" />

    <!-- the following image will be extracted as a whole -->
    <img lang="en" src="x.png" alt="localizable image" />

    <!-- the following image 'alt' and 'title' attributes will NOT be extracted -->
    <img lang="" src="x.png" alt="non-localizable alt attribute text" title="non-localizable title attribute text" />

    <!-- the following block will not be localized by default unless the lang="en" option will be provided-->
    <p lang="">
      <ul>
        <li>non-localizable string 1</li>
        <li lang="en">localizable string 2</li>
      </ul>
    </p>
</div>

<div id="content">
    <!-- <h1>..<h7>, <p> and <li> will be translated by default unless the lang="" attribute is set on them -->

    <h2>Table of Contents</h2>
    <ul>
        <!-- in the following two lines, the <li> will not be translated as it contains
        the only <a> tag that is explicitly told to be the translation item -->
        <li><a lang="en" href="#topic1">Topic 1</a></li>
        <li><a lang="en" href="#topic2">Topic 2</a></li>

        <!-- in the subsequent lines, the <li> item will be the default translation item (default behavior) -->
        <li><a href="#topic3">Topic 3</a></li>
    </ul>

    <h2 id="topic1">Topic 1</h2>
    <p>Paragraph 1</p>

    <h2 id="topic2">Topic 2</h2>
    <p>Paragraph 2</p>

    <h2 id="topic2">Topic 3</h2>
    <!-- One can manually segment large paragraphs (split them into separate translatable sentences) -->
    <p><span lang="en">Paragraph 3, Sentence 1.</span> <span lang="en">Paragraph 3, Sentence 2.</span></p>

    <ul>
        <li>Item 1</li>
        <li>Item 2</li>
        <li>Item 3</li>
    </ul>
</div><!-- /content -->

<?php include($_SERVER['DOCUMENT_ROOT'] . '/inc/footer.php'); ?>