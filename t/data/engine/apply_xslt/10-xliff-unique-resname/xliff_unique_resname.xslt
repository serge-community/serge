<?xml version="1.0"?>
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform" xmlns:xliff="urn:oasis:names:tc:xliff:document:1.2" xmlns:str="http://exslt.org/strings"
                exclude-result-prefixes="xliff str">
    <xsl:output method="xml" version="1.0" encoding="utf-8" indent="yes"/>

    <xsl:strip-space elements="*"/>

    <xsl:param name="prefix" />

    <xsl:variable name="resname-prefix">
        <xsl:choose>
            <xsl:when test="$prefix"><xsl:value-of select="$prefix"/></xsl:when>
            <xsl:otherwise>
                <xsl:variable name="filename-original" select="/xliff:xliff[1]/xliff:file/@original" />
                <xsl:variable name="full-filename-parts" select="str:tokenize($filename-original, '/')" />
                <xsl:variable name="filename-parts" select="str:tokenize($full-filename-parts[last()], '.')" />
                <xsl:variable name="filename-without-ext" select="$filename-parts[1]" />
                <xsl:value-of select="$filename-without-ext"/>
            </xsl:otherwise>
        </xsl:choose>
    </xsl:variable>            
    
    <xsl:template match="@*|node()">
        <xsl:copy>
            <xsl:apply-templates select="@*|node()"/>
        </xsl:copy>
    </xsl:template>

    <xsl:template match="xliff:trans-unit">

        <xsl:copy>
            <xsl:if test="xliff:note[@from='developer']">
                <xsl:variable name="first_note" select="xliff:note[@from='developer'][1]" />

                <xsl:attribute name="resname">
                    <xsl:value-of select="$resname-prefix"/><xsl:text>.</xsl:text><xsl:value-of select="$first_note"/>
                </xsl:attribute>
            </xsl:if>

            <xsl:apply-templates select="@*|node()"/>
        </xsl:copy>

    </xsl:template>

    <xsl:template match="xliff:context-group"/>

</xsl:stylesheet>
