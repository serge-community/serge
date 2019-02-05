<?xml version="1.0"?>
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
    <xsl:output method="xml" indent="yes" />

    <xsl:param name="filter_comment" />
    <xsl:param name="output_comment" />

    <xsl:template match="/">
        <xsl:apply-templates/>
    </xsl:template>

    <xsl:template match="resources">
        <xsl:copy>
            <xsl:apply-templates select="string[@comment=$filter_comment]"/>
        </xsl:copy>
    </xsl:template>

    <xsl:template match="string">
        <string>
            <xsl:attribute name="name"><xsl:value-of select="@name"/></xsl:attribute>
            <xsl:attribute name="comment"><xsl:value-of select="$output_comment"/></xsl:attribute>
            <xsl:value-of select="."/>
        </string>
    </xsl:template>
</xsl:stylesheet>