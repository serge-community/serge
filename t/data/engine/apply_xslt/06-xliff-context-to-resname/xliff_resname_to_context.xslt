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
            <xsl:apply-templates select="@*|node()"/>

            <xsl:if test="@resname">
                <xsl:element name="context-group" namespace="{namespace-uri()}">
                    <xsl:attribute name="name">serge</xsl:attribute>
                    <xsl:attribute name="purpose">x-serge</xsl:attribute>

                    <xsl:element name="context" namespace="{namespace-uri()}">
                        <xsl:attribute name="context-type">x-serge-context</xsl:attribute>
                        <xsl:value-of select="@resname"/>
                    </xsl:element>
                </xsl:element>
            </xsl:if>

        </xsl:copy>

    </xsl:template>

    <xsl:template match="@resname"/>

</xsl:stylesheet>