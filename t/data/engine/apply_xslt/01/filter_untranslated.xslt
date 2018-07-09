<?xml version="1.0"?>
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
    <xsl:output method="xml" indent="yes" />

    <xsl:output method="xml" version="1.0" encoding="utf-8" indent="yes"/>

    <xsl:strip-space elements="*"/>

    <xsl:template match="@*|node()">
        <xsl:copy>
            <xsl:apply-templates select="@*|node()"/>
        </xsl:copy>
    </xsl:template>

    <xsl:template match="resources">
        <xsl:copy>
            <xsl:apply-templates select="string[. != '']"/>
        </xsl:copy>
    </xsl:template>

</xsl:stylesheet>