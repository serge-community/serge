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
            <xsl:if test="xliff:note[@from='developer']">
                <xsl:attribute name="resname">
                    <xsl:value-of select="xliff:note[@from='developer'][1]"/>
                </xsl:attribute>
            </xsl:if>

            <xsl:apply-templates select="@*|node()[not(local-name() = 'note')]"/>

            <xsl:apply-templates select="xliff:note[position() != 1]"/>
        </xsl:copy>

    </xsl:template>

    <!--<xsl:template match="xliff:note"/>-->

</xsl:stylesheet>