<?xml version="1.0"?>
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform" xmlns:xliff="urn:oasis:names:tc:xliff:document:1.2"
                exclude-result-prefixes="xliff">
    <xsl:output method="xml" version="1.0" encoding="utf-8" indent="yes"/>

    <xsl:strip-space elements="*"/>

    <xsl:template match="@*|node()">
        <xsl:copy>
            <xsl:apply-templates select="@*|node()"/>
        </xsl:copy>
    </xsl:template>

    <xsl:template match="xliff:trans-unit">

        <xsl:copy>
            <xsl:if test="xliff:context-group[@purpose='x-serge']/xliff:context[@context-type='x-serge-context']">
                <xsl:attribute name="resname">
                    <xsl:value-of select="xliff:context-group[@purpose='x-serge'][1]/xliff:context[@context-type='x-serge-context'][1]"/>
                </xsl:attribute>
            </xsl:if>

            <xsl:apply-templates select="@*|node()"/>
        </xsl:copy>

    </xsl:template>

    <xsl:template match="xliff:context-group"/>

</xsl:stylesheet>