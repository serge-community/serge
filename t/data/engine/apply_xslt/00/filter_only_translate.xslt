<?xml version="1.0"?>
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
    <xsl:output method="xml" indent="yes" />

    <xsl:template match="/">
        <xsl:apply-templates/>
    </xsl:template>

    <xsl:template match="resources">
        <xsl:copy>
            <xsl:apply-templates select="string[@comment='translate']"/>
        </xsl:copy>
    </xsl:template>

    <xsl:template match="string">
        <string>
            <xsl:attribute name="name"><xsl:value-of select="@name"/></xsl:attribute>
            <xsl:value-of select="."/>
        </string>
    </xsl:template>
</xsl:stylesheet>