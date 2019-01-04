<?xml version="1.0"?>
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform" xmlns:xliff="urn:oasis:names:tc:xliff:document:1.2">
    <xsl:output method="xml" version="1.0" encoding="utf-8" indent="yes"/>

    <xsl:strip-space elements="*"/>

    <xsl:template match="@*|node()">
        <xsl:copy>
            <xsl:apply-templates select="@*|node()"/>
        </xsl:copy>
    </xsl:template>

    <xsl:template match="xliff:trans-unit">
        <xsl:if test="xliff:target/@state = 'translated'">
            <xsl:copy-of select="."/>
        </xsl:if>
    </xsl:template>

</xsl:stylesheet>